require "spec"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"
require "../../src/dsl/builder"

# Global-Source dependents leak: a discarded widget generation must stop being reachable from the
# immortal global Sources (theme/zoom) after a rebuild. `Source#set` is the ONLY @dependents flush and
# theme/zoom are set only on a rare toggle, so without dispose-on-rebuild every rebuild leaves another
# dead generation pinned via Source→node→on_dirty→widget. The faithful headless symptom is
# Theme.current_source_dependent_count: it grows per rebuild when leaking, stays steady when fixed.

private def theme_count : Int32
  CrymbleUI::Theme.current_source_dependent_count
end

private def settle(app)
  CrymbleUI::Testing::TestRenderer.new(400, 300).settle_rendering(app)
end

# Main-tree app: N theme+zoom-reading Dynamic widgets, plus an optional extra section (for the
# removed-subtree discriminator). Collapsed combo boxes are the subjects — each reads Theme/zoom in
# to_primitives and (unlike bare text/buttons, which measure 0 wide without a real font) has an
# explicit width, so it actually renders headlessly and its @primitives_node registers on the sources.
private class LeakApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods
  property rows = 5
  property show_extra = false

  def build : CrymbleUI::Widget
    window("T", 400, 300) do
      vstack do
        rows.times { |i| combo_box(items: ["a", "b"], width: 120.0, id: "r#{i}") { |_i, _v| } }
        if show_extra
          vstack(id: "extra") do
            8.times { |i| combo_box(items: ["a", "b"], width: 120.0, id: "x#{i}") { |_i, _v| } }
          end
        end
      end
    end
  end
end

describe "global-Source dependents leak on rebuild" do
  it "keeps the theme Source's dependent count STEADY across many rebuilds (no per-generation growth)" do
    app = LeakApp.new
    app.build_tree
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    r.settle_rendering(app)
    baseline = theme_count
    baseline.should be > 0 # the Text widgets registered on the theme Source

    counts = [] of Int32
    5.times do
      app.request_rebuild
      r.settle_rendering(app)
      counts << theme_count
    end

    # Fixed: each rebuild disposes the prior generation, so the count never climbs above one live
    # generation. (Leaking, it would be ~baseline*(1..6).) Allow no growth beyond the first settle.
    counts.each { |c| c.should be <= baseline }
  end

  it "drops the count when a theme-reading subtree is REMOVED (discriminates dispose from a copy_state reset)" do
    app = LeakApp.new
    app.show_extra = true
    app.build_tree
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    r.settle_rendering(app)
    with_extra = theme_count

    app.show_extra = false
    app.request_rebuild
    r.settle_rendering(app)
    without_extra = theme_count

    # The removed "extra" subtree's nodes were reachable only from old_root (no new counterpart), so a
    # reset-in-copy_state_from would MISS them; dispose_subtree(old_root) releases them → count drops.
    without_extra.should be < with_extra
  end
end

private def click(app, w)
  b = w.absolute_bounds
  c = CrymbleUI::Vec2.new(b.x + b.width / 2, b.y + b.height / 2)
  app.handle_mouse_down(c)
  app.handle_mouse_up(c)
end

# A combo whose presence can be toggled — for the orphan-reject path (owning combo removed while its
# dropdown is open). The "anchor" combo keeps the tree non-empty when the first is gone.
private class ComboApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods
  property show = true

  def build : CrymbleUI::Widget
    window("T", 400, 300) do
      vstack do
        combo_box(items: ["a", "b", "c"], width: 150.0, id: "c") { |_i, _v| } if show
        combo_box(items: ["z"], width: 80.0, id: "anchor") { |_i, _v| }
      end
    end
  end
end

# Overlay dependents leak: a Dynamic overlay (combo dropdown / menu) reads Theme/zoom too, and lives in
# Window.@overlays (migrated live across rebuilds). It must release its nodes when GENUINELY dropped —
# else every dropdown/menu open→close leaks. (The Menu remove-recreate path menu.cr:287 is traced safe
# by review but is text-width-measured, so its items don't render headlessly and can't be observed
# here — covered by the ComboBox migrate-live oracle below + the reviewers' trace.)
describe "overlay dependents leak on open/close" do
  it "clean close (remove_overlay) disposes the popup's nodes — count returns to baseline" do
    app = ComboApp.new
    app.build_tree
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    r.settle_rendering(app)
    base = theme_count
    combo = app.find("c").not_nil!.as(CrymbleUI::ComboBox)

    click(app, combo) # open
    r.settle_rendering(app)
    theme_count.should be > base # the popup + its item rows registered on the theme Source

    popup = combo.current_popup.not_nil!
    click(app, popup.item_widgets[0]) # select → collapse → unmount_popup → remove_overlay → dispose
    r.settle_rendering(app)
    theme_count.should be <= base
  end

  it "orphan reject (owning combo removed while open) disposes the popup — count returns to baseline" do
    app = ComboApp.new
    app.build_tree
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    r.settle_rendering(app)
    base = theme_count
    combo = app.find("c").not_nil!.as(CrymbleUI::ComboBox)

    click(app, combo) # open
    r.settle_rendering(app)

    app.show = false # remove the owning combo while its dropdown is open
    app.request_rebuild
    r.settle_rendering(app) # rebuild → popup migrated, then cleanup_orphaned_overlays rejects + disposes it

    # If this is > base, the orphan re-registered (the rejected orphan keeps parent=window → its layer
    # stays active → next render recreates the node) and the reject-branch dispose is NOT terminal.
    theme_count.should be <= base
  end

  it "rebuild-while-open keeps the migrated popup LIVE — same node identity, still painted (no wrongful dispose)" do
    app = ComboApp.new
    app.build_tree
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    r.settle_rendering(app)
    combo = app.find("c").not_nil!.as(CrymbleUI::ComboBox)

    click(app, combo) # open
    r.settle_rendering(app)
    popup = combo.current_popup.not_nil!
    node_before = popup.primitives_node
    node_before.should_not be_nil # the popup rendered its own node

    app.request_rebuild # rebuild WHILE open — popup is migrated live into the new window
    r.settle_rendering(app)

    combo2 = app.find("c").not_nil!.as(CrymbleUI::ComboBox)
    popup2 = combo2.current_popup.not_nil!
    popup2.should be(popup) # same migrated instance, still owned by the reconciled combo
    # NODE IDENTITY is the real oracle: a wrongful live-dispose would nil the widget's @primitives_node
    # and get_primitives would mint a DIFFERENT node on the next render (self-healing hides it from a
    # disposition/pixels check). Same object ⇒ the migrated-live popup was never disposed.
    popup2.primitives_node.should be(node_before)
    popup2.has_valid_primitive_cache?.should be_true # and it re-rendered (live, not stranded)
  end
end
