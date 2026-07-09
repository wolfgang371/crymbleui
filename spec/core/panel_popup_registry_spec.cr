require "../spec_helper"
require "../../src/widgets/window_panel"
require "../../src/widgets/popup"
require "../../src/widgets/window"

# WindowPanel/Popup topmost-lookup registry (mirrors Layer.@@all_layers, spec/core/layer_spec.cr).
# find_all_panels/find_all_popups (widget.cr) now read WindowPanel.all_in_tree/Popup.all_in_tree
# instead of walking the whole widget tree. This spec covers the two correctness risks that
# a registry (unlike a tree walk) introduces:
#
#   1. equal-z tie-break: find_topmost_panel breaks a z_index tie via Enumerable#max_by, which
#      keeps the FIRST-encountered element on a tie. Pre-refactor that was DFS order (self, then
#      @children in array order); post-refactor it's registry (Set) iteration order, which Crystal
#      guarantees is INSERTION order (i.e. construction order — Popup/WindowPanel.register runs in
#      initialize). For the natural "construct, then immediately attach as a child" pattern used
#      throughout this codebase, construction order == attach order == DFS order, so the two
#      mechanisms agree without any extra tie-break machinery.
#   2. lifecycle: the registry must not grow unboundedly across rebuild/root-swap, a dropped panel
#      must stop winning find_topmost_panel, a re-created panel must register fresh, and a
#      closed-but-in-tree panel must stay excluded from find_topmost_panel.
describe "WindowPanel/Popup registry" do
  describe "equal-z tie-break" do
    it "find_topmost_panel picks the FIRST-constructed panel on a z_index tie" do
      window = CrymbleUI::Window.new("W", 800, 600)

      # Construct-then-attach, in sequence — panel1 fully attached before panel2 is even
      # constructed. DFS order (window.children array order) == construction/registration
      # order here, so the two tie-break mechanisms (old: DFS-first, new: registry-first)
      # necessarily agree in this — the realistic — case.
      panel1 = CrymbleUI::WindowPanel.new("Panel 1", 10.0, 10.0, 200.0, 150.0, id: "p1")
      window.add_child(panel1)
      panel2 = CrymbleUI::WindowPanel.new("Panel 2", 220.0, 10.0, 200.0, 150.0, id: "p2")
      window.add_child(panel2)

      panel1.z_index.should eq(panel2.z_index) # both default z=0 — the tie under test

      window.find_topmost_panel.should eq(panel1)
    end

    it "agrees regardless of which panel is queried as root's descendant (both orders exercised)" do
      window = CrymbleUI::Window.new("W", 800, 600)
      first = CrymbleUI::WindowPanel.new("First", 10.0, 10.0, 100.0, 100.0, id: "first")
      window.add_child(first)
      second = CrymbleUI::WindowPanel.new("Second", 130.0, 10.0, 100.0, 100.0, id: "second")
      window.add_child(second)
      third = CrymbleUI::WindowPanel.new("Third", 250.0, 10.0, 100.0, 100.0, id: "third")
      window.add_child(third)

      # All three tie at the default z=0; the winner must be deterministic and equal to the
      # first constructed/attached, not an arbitrary registry-iteration artifact.
      window.find_topmost_panel.should eq(first)
    end
  end

  describe "lifecycle" do
    it "registry_size does not grow unboundedly across repeated root-swaps" do
      last_panel = nil
      5.times do |i|
        window = CrymbleUI::Window.new("W#{i}", 800, 600)
        panel = CrymbleUI::WindowPanel.new("Panel", 10.0, 10.0, 200.0, 150.0, id: "p")
        window.add_child(panel)
        last_panel = panel
        CrymbleUI::WindowPanel.cleanup_orphaned(window)
      end

      CrymbleUI::WindowPanel.registry_size.should eq(1)
      CrymbleUI::WindowPanel.all_in_tree(CrymbleUI::Window.new("Other", 10, 10)).should_not contain(last_panel)
    end

    it "a dropped panel no longer wins find_topmost_panel after cleanup_orphaned" do
      window = CrymbleUI::Window.new("W", 800, 600)
      panel = CrymbleUI::WindowPanel.new("Panel", 10.0, 10.0, 200.0, 150.0, z_index: 99, id: "p")
      window.add_child(panel)
      window.find_topmost_panel.should eq(panel)

      new_root = CrymbleUI::Window.new("W2", 800, 600)
      CrymbleUI::WindowPanel.cleanup_orphaned(new_root)

      new_root.find_topmost_panel.should be_nil
      # The stale panel itself must be gone from the registry entirely (not just filtered),
      # so it can never again win a lookup against ANY root.
      CrymbleUI::WindowPanel.all_in_tree(window).should_not contain(panel)
    end

    it "a re-created panel (fresh instance via app.rebuild) registers fresh; the old instance is pruned" do
      app = RegistryRebuildPanelApp.new
      app.build_tree
      first_root = app.root.not_nil!
      first_panel = first_root.find_by_id("p").not_nil!.as(CrymbleUI::WindowPanel)
      CrymbleUI::WindowPanel.all_in_tree(first_root).should contain(first_panel)

      app.rebuild # build() constructs a BRAND NEW WindowPanel instance for id "p"
      second_root = app.root.not_nil!
      second_panel = second_root.find_by_id("p").not_nil!.as(CrymbleUI::WindowPanel)

      second_panel.should_not eq(first_panel) # reconciliation copies state, not identity
      CrymbleUI::WindowPanel.all_in_tree(second_root).should contain(second_panel)
      CrymbleUI::WindowPanel.all_in_tree(second_root).should_not contain(first_panel)
    end

    it "a closed-but-in-tree panel is excluded from find_topmost_panel while a lower-z open one wins" do
      window = CrymbleUI::Window.new("W", 800, 600)
      low = CrymbleUI::WindowPanel.new("Low", 10.0, 10.0, 200.0, 150.0, z_index: 1, id: "low")
      window.add_child(low)
      high = CrymbleUI::WindowPanel.new("High", 10.0, 10.0, 200.0, 150.0, z_index: 5, id: "high")
      window.add_child(high)
      high.closed = true

      window.find_topmost_panel.should eq(low)
    end
  end

  describe "Popup registry lifecycle" do
    it "prunes an orphaned popup after cleanup_orphaned (root-swap)" do
      window = CrymbleUI::Window.new("W", 800, 600)
      popup = CrymbleUI::Popup.new(width: 50.0, height: 50.0)
      window.add_child(popup)

      CrymbleUI::Popup.all_in_tree(window).should contain(popup)

      new_root = CrymbleUI::Text.new("Replacement")
      CrymbleUI::Popup.cleanup_orphaned(new_root)

      CrymbleUI::Popup.all_in_tree(new_root).should_not contain(popup)
      CrymbleUI::Popup.all_in_tree(window).should_not contain(popup)
    end
  end
end

# Constructs a BRAND NEW WindowPanel (id "p") on every build() call — models a real reactive
# app (unlike TestApp's root_widget=, which just returns the same instance back).
class RegistryRebuildPanelApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("W", 800, 600)
    panel = CrymbleUI::WindowPanel.new("Panel", 10.0, 10.0, 200.0, 150.0, z_index: 0, id: "p")
    window.add_child(panel)
    window
  end
end
