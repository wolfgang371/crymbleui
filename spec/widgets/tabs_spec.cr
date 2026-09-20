require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# Tabs: one page visible at a time, the others BUILT BUT HIDDEN.
#
# "Built but hidden" is the whole design, not an implementation detail, and it is what these
# examples pin. A tab that is not shown still has its widgets in the tree, so ids stay findable
# — and, decisively, the shortcuts its content declared are still registered and still fire.
# Shortcuts are registered at BUILD time into the ShortcutManager, scoped by panel, and dispatch
# looks up panel -> shortcut -> handler with no visibility test; so a design that built tab pages
# lazily would silently drop half a panel's shortcuts the moment it was switched away from.
#
# Modelled on TreeNode, which solves the same problem for collapsed children: the children stay
# in @children and are zero_bounds!'d so they cannot render at stale positions.
class TabsTestApp < CrymbleUI::App
    state fired : String = ""

    def build : CrymbleUI::Widget
        window("Tabs", 500, 400) do
            window_panel("P", 10.0, 10.0, 460.0, 360.0, id: "panel") do
                tabs(id: "t") do
                    tab("First") do
                        text("first page", id: "first_text")
                        button("A", "^J", id: "btn_a") { self.fired = "A" }
                    end
                    tab("Second") do
                        text("second page", id: "second_text")
                        button("B", "^K", id: "btn_b") { self.fired = "B" }
                    end
                end
            end
        end
    end
end

private def ctrl_key(code : SF::Keyboard::Key) : SF::Event::KeyEvent
    event = SF::Event::KeyPressedEvent.new
    {% if flag?(:darwin) %}
        event.system = true
        event.control = false
    {% else %}
        event.control = true
        event.system = false
    {% end %}
    event.alt = false
    event.shift = false
    event.code = code
    event
end

describe "Tabs" do
    it "lays out the active page and gives the inactive one no bounds" do
        renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
        app = TabsTestApp.new
        CrymbleUI::Widget.app = app
        app.build_tree
        renderer.render_frame(app)

        app.find("first_text").not_nil!.bounds.height.should be > 0.0
        # Present in the tree, but occupying nothing — the TreeNode rule, so a hidden page
        # cannot paint at stale coordinates.
        app.find("second_text").not_nil!.bounds.height.should eq(0.0)
    end

    it "gives the active page the WHOLE body, not just room for its content" do
        # The page is the body: it has to fill the box under the strip. Laid out loosely it
        # shrank to its content — a 52px-wide page inside a 380px panel — and everything else
        # followed from that: the body frame was drawn around a small box instead of the body, a
        # ScrollView inside got bounds that did not match what was painted (stale ink while
        # scrolling), and widgets were squeezed out mid-resize and came back afterwards.
        renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
        app = TabsTestApp.new
        CrymbleUI::Widget.app = app
        app.build_tree
        renderer.render_frame(app)

        tabs = app.find("t").not_nil!.as(CrymbleUI::Tabs)
        page = tabs.pages.first
        strip_height = tabs.strip.bounds.height

        # Minus the border it is inset by: the body box's edges sit BESIDE the page, never over
        # it — siblings may not overlap, and the renderer asserts exactly that.
        b = CrymbleUI::Tabs::BORDER
        page.bounds.width.should eq(tabs.bounds.width - b * 2)
        page.bounds.height.should eq(tabs.bounds.height - strip_height - b)
    end

    it "keeps the body edges clear of the page — siblings may not overlap" do
        # The renderer enforces this ("siblings no-overlap") and degrades the frame when it is
        # broken; laying the edges ACROSS the page is what produced stray grey boxes in the field
        # list and an exception on Ctrl+0. Asserted here so it cannot creep back silently.
        renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
        app = TabsTestApp.new
        CrymbleUI::Widget.app = app
        app.build_tree
        renderer.render_frame(app)

        tabs = app.find("t").not_nil!.as(CrymbleUI::Tabs)
        page = tabs.pages.first
        tabs.children.each do |child|
            next if child.same?(page) || child.same?(tabs.strip)
            a = child.bounds
            p = page.bounds
            overlaps = a.x < p.x + p.width && p.x < a.x + a.width &&
                       a.y < p.y + p.height && p.y < a.y + a.height
            overlaps.should be_false
        end
    end

    it "switches page when a tab header is clicked" do
        renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
        app = TabsTestApp.new
        CrymbleUI::Widget.app = app
        app.build_tree
        renderer.render_frame(app)

        app.find("t_tab_1").not_nil!.as(CrymbleUI::TabHeader).trigger_click
        renderer.render_frame(app)

        app.find("second_text").not_nil!.bounds.height.should be > 0.0
        app.find("first_text").not_nil!.bounds.height.should eq(0.0)
    end

    it "keeps the inactive page's widgets findable by id" do
        app = TabsTestApp.new
        CrymbleUI::Widget.app = app
        app.build_tree

        app.find("btn_b").should_not be_nil # page 2 is not shown, but it exists
    end

    # The strip has to READ as tabs, and say which one you are on, without anyone having to be
    # told. Asserted on the primitives rather than on a screenshot: the active tab carries the
    # page's own background and deliberately leaves its bottom edge open, which is what makes it
    # look joined to the page below, while an inactive one is filled with the dimmer title-bar
    # colour and closed off along the baseline.
    it "draws the active tab joined to the page and the inactive one closed off" do
        app = TabsTestApp.new
        CrymbleUI::Widget.app = app
        app.build_tree

        first = app.find("t_tab_0").not_nil!.as(CrymbleUI::TabHeader)
        second = app.find("t_tab_1").not_nil!.as(CrymbleUI::TabHeader)
        box = CrymbleUI::Rect.new(0.0, 0.0, 80.0, 26.0)

        fills_of = ->(w : CrymbleUI::TabHeader) {
            w.to_primitives(box).select(CrymbleUI::FillRect).map(&.color)
        }
        page = CrymbleUI::Theme.current.panel_background
        # Active carries the page's own colour; inactive is RECESSED, derived from it rather than
        # borrowed from the title bar — the saturated chrome colour read as "selected" and
        # inverted the whole thing. (The tab headers are LEAVES, so they may paint; the page
        # they sit on may not — see TabPage.)
        fills_of.call(first).should contain(page)
        fills_of.call(second).should contain(page.darken(0.08))
        fills_of.call(second).should_not contain(page)
        # The accent bar is the signal you can see from across the room, and only the active tab
        # wears one.
        fills_of.call(first).should contain(CrymbleUI::Theme.current.panel_title_bar_active)
        fills_of.call(second).should_not contain(CrymbleUI::Theme.current.panel_title_bar_active)

        # The open bottom edge is the whole trick, so it is worth asserting rather than assuming:
        # count the lines that run along the bottom of the box.
        # Edges are thin filled RECTS, not lines: a 1px line is centred on its coordinate, so one
        # at x=0 is half outside the widget and clipped to nothing — which is exactly how the
        # leftmost vertical went missing in the field.
        bottom_lines = ->(w : CrymbleUI::TabHeader) {
            w.to_primitives(box).select(CrymbleUI::FillRect).count { |r| r.bounds.y >= box.height - 1.0 }
        }
        bottom_lines.call(first).should eq(0)  # active: joined to its page
        bottom_lines.call(second).should eq(1) # inactive: closed off
    end

    it "runs the baseline on past the last tab, at the tabs' own bottom edge" do
        # Without this line the strip reads as a row of buttons rather than tabs. It is drawn at
        # the filler's BOTTOM, so the filler has to be stretched to the strip's height — if it
        # collapsed to nothing the line would float at the top of the strip and the effect would
        # be exactly inverted.
        renderer = CrymbleUI::Testing::TestRenderer.new(500, 400)
        app = TabsTestApp.new
        CrymbleUI::Widget.app = app
        app.build_tree
        renderer.render_frame(app)

        tabs = app.find("t").not_nil!.as(CrymbleUI::Tabs)
        filler = tabs.strip.children.last
        first_tab = app.find("t_tab_0").not_nil!

        filler.bounds.height.should eq(first_tab.bounds.height) # stretched, not collapsed
        filler.bounds.width.should be > 0.0                     # and it reaches past the tabs
    end

    it "fires a shortcut declared in the INACTIVE tab" do
        manager = CrymbleUI::ShortcutManager.new
        CrymbleUI::Widget.shortcut_manager = manager
        app = TabsTestApp.new
        CrymbleUI::Widget.app = app
        app.build_tree

        panel = app.find("panel").not_nil!
        # Tab 1 is showing; "^K" belongs to the hidden tab 2. It must still fire: the user is on
        # the panel, and which page happens to be forward is not something a shortcut should care
        # about.
        manager.handle_key_event(ctrl_key(SF::Keyboard::Key::K), panel).should be_true
        app.@fired.should eq("B")
    end
end
