require "../spec_helper"
require "../../src/layout/flow"

describe CrymbleUI::FlowLayout do
    describe "#initialize" do
        it "defaults spacings and padding to 0" do
            f = CrymbleUI::FlowLayout.new
            f.hspacing.should eq(0.0)
            f.vspacing.should eq(0.0)
            f.padding.should eq(0.0)
        end

        it "accepts custom spacings and padding" do
            f = CrymbleUI::FlowLayout.new(hspacing: 8.0, vspacing: 4.0, padding: 2.0)
            f.hspacing.should eq(8.0)
            f.vspacing.should eq(4.0)
            f.padding.should eq(2.0)
        end

        it "starts with no children" do
            f = CrymbleUI::FlowLayout.new
            f.children.should be_empty
        end
    end

    describe "#measure" do
        it "zero size with no children (plus padding)" do
            f = CrymbleUI::FlowLayout.new(padding: 3.0)
            size = f.measure(CrymbleUI::BoxConstraints.new)
            size.width.should eq(6.0)
            size.height.should eq(6.0)
        end

        it "fits all children on one row when they don't overflow" do
            f = CrymbleUI::FlowLayout.new(hspacing: 5.0)
            f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 20.0)))
            f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(30.0, 30.0)))
            f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(40.0, 10.0)))

            size = f.measure(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(200.0, 100.0)))
            # Widths: 50 + 5 + 30 + 5 + 40 = 130
            size.width.should eq(130.0)
            # Max height: 30
            size.height.should eq(30.0)
        end

        it "wraps to a new row when next child overflows available width" do
            f = CrymbleUI::FlowLayout.new(hspacing: 5.0, vspacing: 4.0)
            # Three 40-wide items in a 100-wide container: 40,5,40 = 85 (row 1 = 2 items),
            # then 5+40 would be 130 > 100 → wrap. Row 2 = 1 item.
            3.times { f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(40.0, 20.0))) }
            size = f.measure(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(100.0, 999.0)))
            # Row 1 width: 40 + 5 + 40 = 85; Row 2 width: 40 → used_width = 85
            size.width.should eq(85.0)
            # 2 rows × 20 + 1 vspacing of 4 = 44
            size.height.should eq(44.0)
        end

        it "a child wider than the container gets its own row" do
            f = CrymbleUI::FlowLayout.new(hspacing: 5.0, vspacing: 4.0)
            f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(30.0, 10.0)))
            f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 20.0)))  # oversized
            f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(30.0, 10.0)))
            size = f.measure(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(100.0, 999.0)))
            # Rows: [30] (can't fit 200), [200], [30] → 3 rows
            # Heights: 10 + 20 + 10 = 40; + 2*4 vspacing = 48
            size.height.should eq(48.0)
            # Width clamped to max_width (constraints.constrain) — caller's overflow handling
            size.width.should be <= 100.0
        end

        it "includes padding in reported size" do
            f = CrymbleUI::FlowLayout.new(hspacing: 0.0, padding: 7.0)
            f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 20.0)))
            size = f.measure(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(200.0, 100.0)))
            # Content 50x20 + padding 2*7 = 64x34
            size.width.should eq(64.0)
            size.height.should eq(34.0)
        end
    end

    describe "#perform_layout" do
        it "positions children left-to-right on a single row" do
            f = CrymbleUI::FlowLayout.new(hspacing: 5.0)
            a = TestWidget.new(measured_size: CrymbleUI::Size.new(40.0, 20.0))
            b = TestWidget.new(measured_size: CrymbleUI::Size.new(30.0, 15.0))
            f.add_child(a)
            f.add_child(b)

            constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(200.0, 100.0))
            f.layout(constraints, CrymbleUI::Vec2.new(10.0, 20.0))

            # Children use parent-relative coordinates (matches HStack/VStack convention)
            a.bounds.x.should eq(0.0)     # padding(0) + 0
            a.bounds.y.should eq(0.0)
            b.bounds.x.should eq(45.0)    # 0 + 40 + 5 hspacing
            b.bounds.y.should eq(0.0)     # same row
        end

        it "wraps to a new row when the next child doesn't fit" do
            f = CrymbleUI::FlowLayout.new(hspacing: 5.0, vspacing: 4.0)
            3.times { f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(40.0, 20.0))) }

            constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(100.0, 999.0))
            f.layout(constraints, CrymbleUI::Vec2.zero)

            ch = f.children
            # Row 1: child 0 at x=0, child 1 at x=45
            ch[0].bounds.x.should eq(0.0)
            ch[0].bounds.y.should eq(0.0)
            ch[1].bounds.x.should eq(45.0)
            ch[1].bounds.y.should eq(0.0)
            # Row 2: child 2 wraps
            ch[2].bounds.x.should eq(0.0)
            ch[2].bounds.y.should eq(24.0)    # row-height 20 + vspacing 4
        end

        it "is adaptive — fewer items per row when container is narrower" do
            make_flow = ->{
                f = CrymbleUI::FlowLayout.new(hspacing: 5.0, vspacing: 4.0)
                5.times { f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(40.0, 20.0))) }
                f
            }

            # Wide container: 5 items fit in one row (5*40 + 4*5 = 220)
            wide = make_flow.call
            wide.layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(300.0, 999.0)), CrymbleUI::Vec2.zero)
            wide.children.all? { |c| c.bounds.y == 0.0 }.should be_true

            # Narrow container: only 2 per row (2*40 + 5 = 85 fits, adding another needs 5+40 = 130)
            narrow = make_flow.call
            narrow.layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(100.0, 999.0)), CrymbleUI::Vec2.zero)
            ys = narrow.children.map(&.bounds.y).uniq.sort
            ys.size.should be >= 2   # at least two rows
        end

        # The SAME instance narrow→wide: a FlowLayout re-packs rows against the available width, but its
        # own size is the widest row (sub-max), so the layout relaxation-skip (which treats a sub-max body
        # as intrinsic) would wrongly SKIP the re-flow on a grow and leave the stale, too-tall row layout.
        # FlowLayout opts out of that skip (layout_depends_on_available_space?). Guards that.
        it "re-flows the SAME instance when a width grow lets children collapse to fewer rows" do
            f = CrymbleUI::FlowLayout.new(hspacing: 5.0, vspacing: 4.0)
            3.times { f.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(40.0, 20.0))) }

            # Narrow (100): 40,5,40 fill row 1; the 3rd wraps → 2 rows.
            f.layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(100.0, 999.0)), CrymbleUI::Vec2.zero)
            f.children.map(&.bounds.y).uniq.size.should eq(2)
            narrow_height = f.bounds.height

            # Wide (300): all three fit on one row → 1 row, shorter.
            f.layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(300.0, 999.0)), CrymbleUI::Vec2.zero)
            f.children.map(&.bounds.y).uniq.size.should eq(1)
            f.bounds.height.should be < narrow_height
        end

        # The guard above only proves the flow re-flows when it is CALLED — and it never was. The
        # opt-out is OWN-only, so an ANCESTOR whose own size is sub-max takes the relaxation branch,
        # returns early, and the flow's layout() is never reached. Reported by a beta tester as a
        # filter chip list that stops re-arranging once the panel is widened.
        it "re-flows when an ANCESTOR is re-laid-out at a grown width (the ancestor must not skip)" do
            flow = CrymbleUI::FlowLayout.new(hspacing: 5.0, vspacing: 4.0)
            3.times { flow.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(40.0, 20.0))) }
            outer = CrymbleUI::VStack.new
            outer.add_child(flow)

            outer.layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(100.0, 999.0)), CrymbleUI::Vec2.zero)
            flow.children.map(&.bounds.y).uniq.size.should eq(2)
            narrow_height = outer.bounds.height

            outer.layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(300.0, 999.0)), CrymbleUI::Vec2.zero)
            flow.children.map(&.bounds.y).uniq.size.should eq(1)
            outer.bounds.height.should be < narrow_height
        end
    end
end
