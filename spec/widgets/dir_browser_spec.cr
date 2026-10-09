require "../spec_helper"
require "../../src/widgets/dir_browser"

# Stub File::Info — the adapter only reads `directory?`, and File::Info
# can't be constructed directly outside the stdlib. We wrap a real File.info
# on Dir.tempdir (a directory) and __FILE__ (a file) as cross-platform stand-ins.
private def dir_info : File::Info
    File.info(Dir.tempdir)
end

private def file_info : File::Info
    File.info(__FILE__)
end

describe CrymbleUI::Widgets::DirBrowser::MatrixAdapter do
    describe "click navigation" do
        # Changed 2026-09-12: one click SELECTS a directory, two ENTER it. It used to navigate on
        # the first click, so the same gesture meant different things one row apart — a file needed
        # two clicks to be taken, a directory acted on one. This example asserted the old rule.
        it "clicking a directory entry selects it, and does not navigate yet" do
            adapter = CrymbleUI::Widgets::DirBrowser::MatrixAdapter.new
            adapter.items = [{"../", "", "", dir_info}]
            navigated_to : String? = nil
            selected : String? = nil
            adapter.on_navigate = ->(name : String) { navigated_to = name; nil }
            adapter.on_select_dir = ->(name : String) { selected = name; nil }

            btn = adapter.cell_paint(1, 0).as(CrymbleUI::Button)
            btn.on_click

            navigated_to.should be_nil, "a single click walked into the directory"
            selected.should eq("../"), "a single click must select it, trailing slash and all"
        end

        it "clicking a directory TWICE navigates, with the name stripped of trailing '/'" do
            adapter = CrymbleUI::Widgets::DirBrowser::MatrixAdapter.new
            adapter.items = [{"../", "", "", dir_info}]
            navigated_to : String? = nil
            adapter.on_navigate = ->(name : String) { navigated_to = name; nil }

            adapter.cell_paint(1, 0).as(CrymbleUI::Button).on_click
            adapter.cell_paint(1, 0).as(CrymbleUI::Button).on_click

            navigated_to.should eq("..")
        end

        it "clicking a file entry calls on_select_file (not on_navigate)" do
            adapter = CrymbleUI::Widgets::DirBrowser::MatrixAdapter.new
            adapter.items = [{"hello.txt", "", "", file_info}]
            navigated_to : String? = nil
            selected : String? = nil
            adapter.on_navigate = ->(n : String) { navigated_to = n; nil }
            adapter.on_select_file = ->(n : String) { selected = n; nil }

            btn = adapter.cell_paint(1, 0).as(CrymbleUI::Button)
            btn.on_click

            navigated_to.should be_nil
            selected.should eq("hello.txt")
        end
    end

    describe "double-click accept (UX request)" do
        # User report: double-clicking a file in the file browser should
        # auto-accept the selection (close the dialog with that file).
        # Today the widget treats every click as a single select; this
        # spec drives the change.
        it "second click on the SAME file within the threshold fires on_accept" do
            adapter = CrymbleUI::Widgets::DirBrowser::MatrixAdapter.new
            adapter.items = [{"hello.txt", "", "", file_info}]
            accepted : String? = nil
            adapter.on_accept = ->(n : String) { accepted = n; nil }

            btn1 = adapter.cell_paint(1, 0).as(CrymbleUI::Button)
            btn1.on_click   # first click → just selects

            # Second click on the same row, well within the double-click
            # window. We re-fetch the button because cell_paint constructs
            # a fresh widget each call (the adapter is what holds state).
            btn2 = adapter.cell_paint(1, 0).as(CrymbleUI::Button)
            btn2.on_click

            accepted.should eq("hello.txt")
        end

        # RED FIRST: activation must not expire. The rule is "the first click
        # SELECTS and the second ACTS" — a two-step activation, not a double-click — so a user who
        # selects a row, looks at it, and clicks again must still get the action. This example
        # SLEEPS on purpose and that cannot make it flaky: more delay only makes the assertion
        # more true. It was RED while the predicate consulted the clock.
        it "a second click on the same row acts however long the user took over it" do
            adapter = CrymbleUI::Widgets::DirBrowser::MatrixAdapter.new
            adapter.items = [{"subdir/", "", "", dir_info}]
            nav_calls : Array(String) = [] of String
            adapter.on_navigate = ->(n : String) { nav_calls << n; nil }

            adapter.cell_paint(1, 0).as(CrymbleUI::Button).on_click
            sleep 0.6.seconds # longer than the 500 ms window this used to be gated on
            adapter.cell_paint(1, 0).as(CrymbleUI::Button).on_click

            nav_calls.should eq(["subdir"]),
              "the second click did not act — activation is still expiring on wall clock"
        end

        # This example is RESTATED rather than deleted. It pinned "two clicks far apart in
        # TIME do not accept" — the old double-click rule for files, the half left behind when
        # activation became a two-step gesture. Time is no longer what separates two clicks;
        # the ROW is. So the surviving contract is the one that still protects the user from an
        # accidental accept: a click that lands somewhere else moves the selection instead of
        # completing the previous one.
        it "a click on a DIFFERENT row does not accept — selection moves, it does not accumulate" do
            adapter = CrymbleUI::Widgets::DirBrowser::MatrixAdapter.new
            adapter.items = [{"hello.txt", "", "", file_info}, {"other.txt", "", "", file_info}]
            accepted : String? = nil
            selected : Array(String) = [] of String
            adapter.on_accept = ->(n : String) { accepted = n; nil }
            adapter.on_select_file = ->(n : String) { selected << n; nil }

            adapter.cell_paint(1, 0).as(CrymbleUI::Button).on_click # select hello.txt
            adapter.cell_paint(2, 0).as(CrymbleUI::Button).on_click # a DIFFERENT row

            accepted.should be_nil, "clicking a different row completed the previous row's activation"
            selected.should eq(["hello.txt", "other.txt"]), "the second click did not re-select"

            # ...and the row now selected still accepts on ITS second click.
            adapter.cell_paint(2, 0).as(CrymbleUI::Button).on_click
            accepted.should eq("other.txt")
        end

        it "double-clicking a DIRECTORY navigates ONCE (does not fire on_accept)" do
            adapter = CrymbleUI::Widgets::DirBrowser::MatrixAdapter.new
            adapter.items = [{"subdir/", "", "", dir_info}]
            accepted : String? = nil
            nav_calls : Array(String) = [] of String
            adapter.on_accept = ->(n : String) { accepted = n; nil }
            adapter.on_navigate = ->(n : String) { nav_calls << n; nil }

            adapter.cell_paint(1, 0).as(CrymbleUI::Button).on_click
            adapter.cell_paint(1, 0).as(CrymbleUI::Button).on_click

            accepted.should be_nil, "a directory is never ACCEPTED as the chosen file"
            # Was 2, when every click navigated. The first click now selects, so a double-click
            # enters the directory exactly once — which is what the gesture means everywhere else.
            nav_calls.size.should eq(1)
            nav_calls.first.should eq("subdir")
        end
    end
end
