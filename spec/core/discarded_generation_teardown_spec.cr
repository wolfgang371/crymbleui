require "../spec_helper"
require "../../src/testing/test_renderer"

# A discarded widget generation must be UNLINKED, not merely dropped.
#
# Boehm scans conservatively: one stale word that happens to look like a pointer pins one node,
# and because a widget generation is a densely-linked graph (parent <-> children, and every
# rendered widget holds multi-megabyte backends), that single false positive keeps the WHOLE
# generation — and all its textures — alive. Measured on the embrace app: a discarded generation
# held 522 live backends; breaking the links released 330 of them (63%) in one collection.
#
# So teardown is not about "helping the GC" in general — it is about making a false positive
# cost ONE node instead of half a gigabyte. `dispose_subtree` already runs on the discarded root
# on every rebuild (App#rebuild); this pins that it also severs the graph and drops the
# generation's backend references.
#
# It releases the PAYLOAD too, not just the reference. That is safe only because `copy_state_from`
# TRANSFERS @background_backend to the reconciled widget (adopt + relinquish) instead of copying
# it: a background still present on a discarded widget is therefore provably unshared, so nobody
# live can be drawing with it. While both sides held the same object this was NOT safe, and the
# resulting "release references only" policy is what left every discarded texture resident under
# SFML — see spec/core/layer_hosted_backend_release_spec.cr for the other half of that leak.

private class TeardownApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Teardown", 400, 300) do
      vstack do
        4.times { |i| combo_box(items: ["a", "b"], width: 120.0, id: "c#{i}") { |_i, _v| } }
      end
    end
  end
end

private def each_widget(w : CrymbleUI::Widget, &block : CrymbleUI::Widget ->)
  block.call(w)
  w.children.each { |c| each_widget(c, &block) }
end

describe "discarded generation teardown" do
  it "unlinks the old tree and releases its backend references on rebuild" do
    app = TeardownApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    renderer.settle_rendering(app)

    old_root = app.root.not_nil!
    old_root.children.should_not be_empty

    # Non-vacuity: capture a descendant that ACTUALLY holds a rendered texture, so the
    # post-rebuild nil assertion cannot pass trivially.
    holder : CrymbleUI::Widget? = nil
    each_widget(old_root) { |w| holder = w if holder.nil? && w.widget_backend }
    holder.should_not be_nil, "no widget rendered to its own backend — the fixture proves nothing"
    deep = holder.not_nil!

    app.request_rebuild
    renderer.settle_rendering(app)

    # The discarded generation is severed: no links, no backend references.
    old_root.children.should be_empty,
      "the discarded root still links #{old_root.children.size} children — one conservatively " \
      "retained node would pin the entire generation"
    deep.widget_backend.should be_nil
    deep.background_backend.should be_nil
    # @parent is deliberately KEPT: clearing the DOWNWARD links is what breaks the cascade, while
    # a migrated overlay (an open popup surviving a rebuild) reaches the LIVE window through a
    # chain running via old-tree widgets, and focus/find_window walk it — see
    # spec/widgets/combo_box_reconcile_focus_spec.cr, which fails if this is severed.
    deep.parent.should_not be_nil
  end

  it "leaves the LIVE tree fully intact (teardown must not touch the new generation)" do
    app = TeardownApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    renderer.settle_rendering(app)

    app.request_rebuild
    renderer.settle_rendering(app)

    live_root = app.root.not_nil!
    live_root.children.should_not be_empty
    rendered = 0
    each_widget(live_root) { |w| rendered += 1 if w.widget_backend }
    rendered.should be > 0, "the live generation lost its backends — teardown hit the wrong tree"
    each_widget(live_root) { |w| w.children.each { |c| c.parent.should_not be_nil } }
  end
end
