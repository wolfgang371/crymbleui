require "../spec_helper"
require "../../src/layout/flow"
require "../../src/layout/vstack"
require "../../src/widgets/expanded"
require "../../src/widgets/tree_node"
require "../../src/widgets/scroll_view"
require "../../src/widgets/window_panel"
require "../../src/testing/test_renderer"

# The relaxation-skip (Widget#can_skip_layout?) treats a body whose own size is BELOW the offered
# maximum as intrinsic: more space cannot change it, so the whole subtree is skipped. That is false for
# any subtree CONTAINING a wrapping layout — a FlowLayout re-packs against max_width while its own size
# stays the widest row. FlowLayout declares that with layout_depends_on_available_space?, but the
# declaration is OWN-only: an ancestor that is itself sub-max skips and never calls the flow at all.
#
# The three conditions below are what make the defect observable, and all three are required (a wholly
# skipping ancestor moves nothing, so nothing overlaps):
#   1. the outer container is given a TIGHT width  (a panel hands Content BoxConstraints.tight)
#   2. at least one SUB-MAX intermediate sits between the outer and the flow
#   3. the outer is FORCED to re-lay-out (models Content#can_skip_layout? => false)
private def build_nested_flow(chip_w = 70.0, chips = 5)
    flow = CrymbleUI::FlowLayout.new(hspacing: 5.0, vspacing: 4.0, id: "chips")
    chips.times { flow.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(chip_w, 20.0))) }
    inner = CrymbleUI::VStack.new(id: "inner")   # condition 2: sizes to its content, stays sub-max
    inner.add_child(flow)
    {flow, inner}
end

private def rows_of(flow : CrymbleUI::FlowLayout) : Int32
    flow.children.map(&.bounds.y).uniq.size
end

# Row count of a FRESHLY built tree at the same width — the oracle for "did it pack correctly?".
# Never compare against a literal: the expected count depends on font/spacing metrics.
private def fresh_rows_at(width : Float64, chip_w = 70.0, chips = 5) : Int32
    flow, inner = build_nested_flow(chip_w, chips)
    outer = CrymbleUI::VStack.new
    outer.add_child(inner)
    outer.layout(CrymbleUI::BoxConstraints.new(min_width: width, max_width: width,
                                               min_height: 0.0, max_height: 400.0), CrymbleUI::Vec2.zero)
    rows_of(flow)
end

private def tight(width : Float64, height = 400.0) : CrymbleUI::BoxConstraints
    CrymbleUI::BoxConstraints.new(min_width: width, max_width: width, min_height: 0.0, max_height: height)
end

describe "relaxation-skip over a wrapping descendant" do
    it "re-packs the flow when the outer is re-laid-out at a grown width" do
        flow, inner = build_nested_flow
        outer = CrymbleUI::VStack.new
        outer.add_child(inner)

        outer.layout(tight(240.0), CrymbleUI::Vec2.zero)
        narrow_rows = rows_of(flow)
        narrow_rows.should eq(fresh_rows_at(240.0))

        outer.mark_needs_layout # condition 3
        outer.layout(tight(600.0), CrymbleUI::Vec2.zero)
        rows_of(flow).should eq(fresh_rows_at(600.0))
        rows_of(flow).should be < narrow_rows
    end

    # The user-visible damage: the outer advances its cursor over a subtree that kept its stale (tall)
    # extent, so the next sibling is pulled up into it. In the reported bug that sibling is the
    # Perspective, which ends up drawn on top of the filter list.
    it "never places the following sibling above the flow's bottom after a width grow" do
        flow, inner = build_nested_flow
        fill = CrymbleUI::Expanded.new
        fill.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(30.0, 10.0)))
        outer = CrymbleUI::VStack.new
        outer.add_child(inner)
        outer.add_child(fill)

        outer.layout(tight(240.0), CrymbleUI::Vec2.zero)
        outer.mark_needs_layout
        outer.layout(tight(600.0), CrymbleUI::Vec2.zero)

        # Compare against the flow's OWN bottom, not its parent's height — the parent's height is
        # exactly the stale value that lies when the subtree was skipped.
        flow_bottom = flow.bounds.y + flow.bounds.height + inner.bounds.y
        fill.bounds.y.should be >= flow_bottom
    end

    it "keeps packing correct across several wrap boundaries on ONE instance" do
        flow, inner = build_nested_flow
        outer = CrymbleUI::VStack.new
        outer.add_child(inner)

        [240.0, 400.0, 600.0, 400.0, 240.0].each do |w|
            outer.mark_needs_layout
            outer.layout(tight(w), CrymbleUI::Vec2.zero)
            rows_of(flow).should eq(fresh_rows_at(w)), "packing wrong at width #{w}"
        end
    end

    it "narrowing keeps re-packing (works today — pinned so the fix cannot invert it)" do
        flow, inner = build_nested_flow
        outer = CrymbleUI::VStack.new
        outer.add_child(inner)

        outer.layout(tight(600.0), CrymbleUI::Vec2.zero)
        wide_rows = rows_of(flow)
        outer.mark_needs_layout
        outer.layout(tight(240.0), CrymbleUI::Vec2.zero)
        rows_of(flow).should be > wide_rows
        rows_of(flow).should eq(fresh_rows_at(240.0))
    end

    # A grow that crosses no wrap boundary must leave the arrangement byte-identical. (Asserting "the
    # skip was still taken" would be wrong here: for a flow-bearing subtree it is by design no longer
    # taken — that is what the perf budget below is for, on a NON-wrapping sibling.)
    it "leaves the arrangement identical when a grow crosses no wrap boundary" do
        flow, inner = build_nested_flow
        outer = CrymbleUI::VStack.new
        outer.add_child(inner)

        outer.layout(tight(600.0), CrymbleUI::Vec2.zero)
        before = flow.children.map { |c| {c.bounds.x, c.bounds.y} }
        outer.mark_needs_layout
        outer.layout(tight(640.0), CrymbleUI::Vec2.zero)
        flow.children.map { |c| {c.bounds.x, c.bounds.y} }.should eq(before)
    end

    # A pure HEIGHT grow re-lays the subtree out (the opt-out is axis-agnostic on purpose: FlowLayout
    # passes the available height down to its children, and an axis-typed predicate would reintroduce a
    # "did the author declare the right axis?" hole of the same class). What must hold is that the
    # PACKING is unchanged — a height grow can never move a chip.
    it "keeps packing identical when only the height grows" do
        flow, inner = build_nested_flow
        outer = CrymbleUI::VStack.new
        outer.add_child(inner)

        outer.layout(tight(400.0, 300.0), CrymbleUI::Vec2.zero)
        before = flow.children.map { |c| {c.bounds.x, c.bounds.y} }
        outer.mark_needs_layout
        outer.layout(tight(400.0, 900.0), CrymbleUI::Vec2.zero)
        flow.children.map { |c| {c.bounds.x, c.bounds.y} }.should eq(before)
        rows_of(flow).should eq(fresh_rows_at(400.0))
    end

    it "lifts through TWO levels of nesting (flow inside a flow)" do
        inner_flow = CrymbleUI::FlowLayout.new(hspacing: 5.0, vspacing: 4.0)
        4.times { inner_flow.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(70.0, 20.0))) }
        wrapper = CrymbleUI::VStack.new
        wrapper.add_child(inner_flow)
        outer_flow = CrymbleUI::FlowLayout.new(hspacing: 5.0, vspacing: 4.0)
        outer_flow.add_child(wrapper)
        mid = CrymbleUI::VStack.new
        mid.add_child(outer_flow)
        outer = CrymbleUI::VStack.new
        outer.add_child(mid)

        outer.layout(tight(240.0), CrymbleUI::Vec2.zero)
        narrow_rows = rows_of(inner_flow)
        outer.mark_needs_layout
        outer.layout(tight(600.0), CrymbleUI::Vec2.zero)
        rows_of(inner_flow).should be < narrow_rows
    end

    # Collapse zeroes the subtree's bounds without laying it out. Re-expanding must restore a correct
    # packing, and collapsing must NOT leave the ancestors permanently pessimised (the flag is cleared
    # by zero_bounds!, so a collapsed section stops forcing re-layout).
    it "re-packs correctly after a collapse / re-expand cycle" do
        flow, inner = build_nested_flow
        node = CrymbleUI::TreeNode.new("Filter", expanded: true)
        node.add_child(inner)
        outer = CrymbleUI::VStack.new
        outer.add_child(node)

        outer.layout(tight(240.0), CrymbleUI::Vec2.zero)
        node.toggle # the real collapse path — `expanded=` alone does NOT mark layout (toggle does)
        outer.layout(tight(240.0), CrymbleUI::Vec2.zero)
        node.toggle
        outer.layout(tight(600.0), CrymbleUI::Vec2.zero)

        rows_of(flow).should eq(fresh_rows_at(600.0))
    end

    # PIN, not a guard: this passes with or without the subtree closure. A ScrollView hands its content
    # a TIGHT width, so the content root already fails the skip on its min_width and re-lays the flow out
    # regardless. Kept so a future ScrollView that loosens that constraint cannot silently open the gap
    # here — but do not read it as coverage of the closure itself.
    it "re-packs a flow nested inside a vertical ScrollView" do
        flow, inner = build_nested_flow
        sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "sv")
        sv.set_content(inner) # NOT add_child — the content branch keys off @content_widget
        outer = CrymbleUI::VStack.new
        outer.add_child(sv)

        outer.layout(tight(240.0), CrymbleUI::Vec2.zero)
        narrow_rows = rows_of(flow)
        outer.mark_needs_layout
        outer.layout(tight(600.0), CrymbleUI::Vec2.zero)
        rows_of(flow).should be < narrow_rows
    end

    # PIN for the one genuinely divergent combination in the repo. TreeNode is the only container that
    # hands its children LOOSE-FINITE constraints, and Expanded(fill_area: true) is the only widget whose
    # perform_layout then returns something OTHER than its measure (constraints.max vs the child's
    # natural size) — so it is the case where advancing the cursor by bounds instead of measure actually
    # changes where the next sibling lands. fill_area: false would exercise the identical-to-measure
    # branch and prove nothing.
    it "keeps a TreeNode's fill Expanded inside the node, below a re-packed flow" do
        flow, inner = build_nested_flow
        node = CrymbleUI::TreeNode.new("Section", expanded: true)
        node.add_child(inner)
        fill = CrymbleUI::Expanded.new(fill_area: true)
        fill.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(30.0, 10.0)))
        node.add_child(fill)
        outer = CrymbleUI::VStack.new
        outer.add_child(node)

        outer.layout(tight(240.0), CrymbleUI::Vec2.zero)
        outer.mark_needs_layout
        outer.layout(tight(600.0), CrymbleUI::Vec2.zero)

        # Node-local coordinates: the fill starts at or below the flow's bottom …
        fill.bounds.y.should be >= (inner.bounds.y + flow.bounds.y + flow.bounds.height)
        # … and does not get pushed out past the node's own extent.
        (fill.bounds.y + fill.bounds.height).should be <= (node.bounds.height + 0.5)
    end

    it "survives a rebuild-style re-layout between two resizes" do
        flow, inner = build_nested_flow
        outer = CrymbleUI::VStack.new
        outer.add_child(inner)

        outer.layout(tight(240.0), CrymbleUI::Vec2.zero)
        # settle: a fully clean tree, the state a rebuild+settle leaves behind
        outer.layout(tight(240.0), CrymbleUI::Vec2.zero)
        outer.layout(tight(600.0), CrymbleUI::Vec2.zero)
        rows_of(flow).should eq(fresh_rows_at(600.0))
    end
end

describe "relaxation-skip perf budget" do
    # The optimization must SURVIVE where nothing wraps: a panel of Buttons still skips its content on a
    # grow. The precondition assertion is the point — without it, a flag that silently became universally
    # true would still read measure_count == 0 here for unrelated reasons.
    it "still skips a grow when the content contains no wrapping layout" do
        renderer = CrymbleUI::Testing::TestRenderer.new(1200, 900)
        app = TestApp.new
        window = CrymbleUI::Window.new("Stress", 1200, 900)
        panel = CrymbleUI::WindowPanel.new("Buttons", 50.0, 100.0, 700.0, 600.0)
        grid = CrymbleUI::VStack.new(spacing: 2.0)
        10.times do |row|
            hs = CrymbleUI::HStack.new(spacing: 2.0)
            10.times { |col| hs.add_child(CrymbleUI::Button.new("#{row},#{col}") { }) }
            grid.add_child(hs)
        end
        panel.add_child(grid)
        window.add_child(panel)
        app.root_widget = window
        renderer.render_frame(app)
        renderer.settle_rendering(app)

        # The point of this example: if the closure ever became universally true, the O(1) grow would be
        # dead everywhere and the counter below would still read 0 for unrelated reasons.
        grid.subtree_layout_depends_on_available_space?.should be_false

        right = panel.x + panel.width
        panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 300.0))
        renderer.render_frame(app)
        CrymbleUI::Widget.reset_measure_count
        panel.on_mouse_move(CrymbleUI::Vec2.new(right + 40.0, panel.y + 300.0))
        renderer.render_frame(app)
        CrymbleUI::Widget.measure_count.should eq(0)
    end

    # FlowLayout must remain the ONLY widget opting out. A common widget (TextInput, ScrollView,
    # DecoratedContainer) adopting it would keep every Button-only fixture green while every real panel
    # loses its O(1) grow — invisible to the budget above.
    it "FlowLayout is the sole layout_depends_on_available_space? override" do
        src = Dir.glob(File.join(__DIR__, "..", "..", "src", "**", "*.cr"))
        overrides = src.select do |f|
            next false if f.ends_with?("core/widget.cr") # the base definition itself
            File.read(f).includes?("def layout_depends_on_available_space?")
        end
        overrides.map { |f| File.basename(f) }.should eq(["flow.cr"])
    end
end
