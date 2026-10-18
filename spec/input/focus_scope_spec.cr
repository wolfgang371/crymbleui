require "../spec_helper"
require "../../src/testing/driver"
require "../../src/testing/configurable_matrix_adapter"
require "../../src/widgets/tabs"
require "../../src/widgets/tree_node"
require "../../src/widgets/multi_combo_box"
require "../../src/widgets/scroll_view"

# The panel in front holds the keyboard, and Tab stays inside it. Whatever raises a panel - a press in it or on its
# title bar, a panel the app opens or reopens, Ctrl+Tab - hands it the keyboard unless the keyboard is already inside:
# to the widget that last held it there, else the panel's home widget, else its first Tab stop, else nobody. Tab,
# Shift+Tab and the arrows move among the Tab stops (focusable, enabled, shown) of the keyboard's panel; every panel
# shortcut goes to the keyboard's panel; Enter and Space go to a focused button first. When the keyboard's panel
# closes or vanishes, the panel in front takes the keyboard.
#
# Everything goes through the Driver, a DSL app (new instances on every build). Each case names in a comment where
# the keyboard went before this rule ("today").

# A DSL app whose window holds what the scene builds; the scene reads the app's state, set by its own handlers.
private class SceneApp < CrymbleUI::App
  getter log = [] of String
  property flags = {} of Symbol => Bool

  def initialize(&@scene : SceneApp -> Nil)
    super()
  end

  def build : CrymbleUI::Widget
    window("W", 1000, 700) { @scene.call(self) }
  end

  def flag?(name : Symbol) : Bool
    @flags.fetch(name, false)
  end

  def set(name : Symbol, value : Bool = true) : Nil
    @flags[name] = value
    request_rebuild
  end
end

private def scene(&block : SceneApp -> Nil) : CrymbleUI::Testing::Driver
  CrymbleUI::Testing::Driver.new(SceneApp.new(&block), 1000, 700)
end

private def keyboard : CrymbleUI::Widget?
  CrymbleUI::Widget.focus_manager.focused_widget
end

private def panel(ui, id : String) : CrymbleUI::WindowPanel
  ui.find(id).as(CrymbleUI::WindowPanel)
end

private def front_id(ui) : String?
  ui.app.root.not_nil!.find_topmost_panel.try(&.id)
end

# Panel A (a1, a combo ac, a2) and panel B (b1, b2) side by side - reading order interleaves them, so before this
# rule the first Tab from a1 went to b1.
private def panel_a(a : SceneApp) : Nil
  a.window_panel("A", 10.0, 150.0, 300.0, 260.0, id: "A") do
    a.vstack do
      a.text_input(id: "a1") { }
      a.combo_box(items: ["x", "y", "z"], id: "ac")
      a.text_input(id: "a2") { }
    end
  end
end

private def panel_b(a : SceneApp, closed_callback : Bool = false) : Nil
  p = a.window_panel("B", 330.0, 150.0, 300.0, 260.0, id: "B") do
    a.vstack do
      a.text_input(id: "b1") { }
      a.text_input(id: "b2") { }
    end
  end
  p.on_closed { a.set(:b_gone) } if closed_callback
end

private def ab : CrymbleUI::Testing::Driver
  scene { |a| panel_a(a); panel_b(a) }
end

private def rebuild(ui) : Nil
  ui.app.request_rebuild
  ui.settle
end

describe "the panel in front holds the keyboard" do
  describe "Tab" do
    it "cycles inside the keyboard's panel, both ways" do
      ui = ab
      ui.type "a1", "k"
      seen = [] of String?
      3.times { ui.press "Tab"; seen << ui.focused_id }
      seen.should eq(["ac", "a2", "a1"]) # today: b1, ac, b2
      back = [] of String?
      3.times { ui.press "Shift+Tab"; back << ui.focused_id }
      back.should eq(["a2", "ac", "a1"])
    end

    it "from a widget of the window body cycles the body's widgets, never a panel's" do
      ui = scene do |a|
        a.hstack { a.text_input(id: "t1") { }; a.text_input(id: "t2") { } }
        panel_a(a)
      end
      ui.type "t1", "k"
      ui.press "Tab"
      ui.focused_id.should eq("t2")
      ui.press "Tab"
      ui.focused_id.should eq("t1") # today: a1, the next in reading order
    end

    it "visits no hidden or disabled widget: not under a collapsed section, not on an inactive tab page" do
      ui = scene do |a|
        a.window_panel("Q", 10.0, 150.0, 400.0, 300.0, id: "Q") do
          a.vstack do
            a.tree_node("Section", expanded: false) { a.text_input(id: "q_hidden") { } }
            dis = a.button("Off", id: "q_off") { }
            dis.enabled = false
            a.text_input(id: "q1") { }
            a.tabs(id: "qt") do
              a.tab("One") { a.text_input(id: "q_page1") { } }
              a.tab("Two") { a.text_input(id: "q_page2") { } }
            end
          end
        end
      end
      ui.type "q1", "k"
      seen = [] of String?
      8.times { ui.press "Tab"; seen << ui.focused_id }
      seen.should_not contain("q_hidden") # today: visited
      seen.should_not contain("q_off")
      seen.should_not contain("q_page2")
      seen.should contain("q_page1")
    end

    it "keeps an open combo list's Tab in its panel" do
      ui = ab
      ui.press "Enter", on: "ac" # the list opens, its filter takes the keyboard
      ui.press "Tab"
      ui.focused_id.should eq("a2") # today: b2 (the cycle went on from ac through the whole window)
    end

    it "keeps an open multi-select list's Tab in its panel, also after a rebuild" do
      ui = scene do |a|
        a.window_panel("A", 10.0, 150.0, 300.0, 260.0, id: "A") do
          a.vstack do
            a.text_input(id: "a1") { }
            a.widget(CrymbleUI::MultiComboBox.new(items: ["x", "y"], selected: Set(Int32).new, id: "am"))
            a.text_input(id: "a2") { }
          end
        end
        panel_b(a)
      end
      ui.press "Enter", on: "am"
      rebuild(ui)
      ui.press "Tab"
      ui.focused_id.should eq("a2") # today: the list's filter declines Tab and the cycle leaves A
    end

    it "from nobody enters the front panel on the widget it last held" do
      ui = scene do |a|
        a.button("vanish", id: "vanish") { a.set(:vanished) } unless a.flag?(:vanished)
        panel_a(a)
      end
      ui.type "a2", "k"
      ui.click "vanish" # the button takes the keyboard, then vanishes with it
      keyboard.should be_nil
      ui.press "Tab"
      ui.focused_id.should eq("a2") # today: the window's first Tab stop
    end

    it "is still a grid's own inside its panel (control)" do
      ui = scene do |a|
        a.window_panel("G", 10.0, 150.0, 400.0, 300.0, id: "G") do
          a.vstack do
            a.text_input(id: "g1") { }
            a.widget(CrymbleUI::VirtualMatrix.new(adapter: ConfigurableMatrixAdapter.new(1, 1, 5, 3, 1, 1), id: "grid"))
          end
        end
      end
      ui.focus_cell "grid", 1, 1
      before = ui.cursor("grid")
      ui.press "Tab"
      ui.focused_id.should eq("grid")
      ui.cursor("grid").should_not eq(before)
    end
  end

  # F6 / Shift+F6 move through all the parts of the keyboard's panel - its Tab stops in reading order - whatever
  # holds the keyboard: a grid that keeps Tab for its cursor gives F6 up (Wolfgang, 2026-10-17). Today F6 does nothing.
  describe "F6" do
    it "moves out of a grid to the panel's next part, where Tab stays in the grid; Shift+F6 back" do
      ui = scene do |a|
        a.window_panel("G", 10.0, 150.0, 400.0, 400.0, id: "G") do
          a.vstack do
            a.text_input(id: "g1") { }
            a.widget(CrymbleUI::VirtualMatrix.new(adapter: ConfigurableMatrixAdapter.new(1, 1, 5, 3, 1, 1), id: "grid"))
            a.text_input(id: "g2") { }
          end
        end
      end
      ui.focus_cell "grid", 1, 1
      ui.press "F6"
      ui.focused_id.should eq("g2")
      ui.press "Shift+F6"
      ui.focused_id.should eq("grid")
      ui.cursor("grid").should eq({1, 1}) # the round trip keeps the grid's cursor
      ui.press "Shift+F6"
      ui.focused_id.should eq("g1")
    end

    # Only F6 and Shift+F6: Ctrl+F6 and Alt+F6 stay an app's. Mutation: drop the modifier guard - the keyboard moves.
    it "leaves Ctrl+F6 to the widget and the app's shortcuts" do
      ui = scene do |a|
        a.window_panel("G", 10.0, 150.0, 400.0, 400.0, id: "G") do
          a.vstack do
            a.widget(CrymbleUI::VirtualMatrix.new(adapter: ConfigurableMatrixAdapter.new(1, 1, 5, 3, 1, 1), id: "grid"))
            a.text_input(id: "g2") { }
          end
        end
      end
      ui.focus_cell "grid", 1, 1
      ui.press "Ctrl+F6"
      ui.focused_id.should eq("grid")
    end

    it "from a widget of the window body walks the body's widgets, never a panel's (as Tab)" do
      ui = scene do |a|
        a.hstack { a.text_input(id: "t1") { }; a.text_input(id: "t2") { } }
        panel_a(a)
      end
      ui.type "t1", "k"
      ui.press "F6"
      ui.focused_id.should eq("t2")
      ui.press "F6"
      ui.focused_id.should eq("t1")
    end

    it "cycles all the parts of the keyboard's panel and stays in it" do
      ui = ab
      ui.type "a1", "k"
      seen = [] of String?
      3.times { ui.press "F6"; seen << ui.focused_id }
      seen.should eq(["ac", "a2", "a1"])
    end

    it "from nobody enters the front panel" do
      ui = ab
      ui.type "a1", "k"
      CrymbleUI::Widget.focus_manager.clear_focus
      ui.press "F6"
      ui.focused_id.should eq("a1")
    end

    it "closes an open list first" do
      ui = ab
      ui.press "Enter", on: "ac"
      ui.find("ac").as(CrymbleUI::ComboBox).popup_open?.should be_true # instrument
      ui.press "F6"
      ui.find("ac").as(CrymbleUI::ComboBox).popup_open?.should be_false
      ui.focused_id.should eq("a2") # closed first, then the walk from the combo
    end
  end

  describe "arrows" do
    private_buttons = ->(a : SceneApp) do
      a.hstack { a.button("body1", id: "body1") { }; a.button("body2", id: "body2") { } }
      a.window_panel("A", 10.0, 150.0, 200.0, 200.0, id: "A") do
        a.vstack { a.button("ab1", id: "ab1") { }; a.button("ab2", id: "ab2") { } }
      end
      a.window_panel("B", 330.0, 150.0, 200.0, 200.0, id: "B") do
        a.vstack { a.button("bb1", id: "bb1") { } }
      end
      nil
    end

    it "do not leave the keyboard's panel" do
      ui = scene { |a| private_buttons.call(a) }
      ui.click "ab1"
      ui.press "Right"
      ui.focused_id.should eq("ab1") # today: bb1, in the panel to the right
      ui.press "Down"
      ui.focused_id.should eq("ab2")
    end

    it "from the window body do not enter a panel" do
      ui = scene { |a| private_buttons.call(a) }
      ui.click "body1"
      ui.press "Down"
      ui.focused_id.should eq("body1") # today: a panel's button below
      ui.press "Right"
      ui.focused_id.should eq("body2")
    end
  end

  describe "a raise hands the keyboard over" do
    it "a press on a title bar: the panel's first stop, then the widget it last held" do
      ui = ab
      ui.type "a2", "k"
      ui.press_title "B"
      ui.focused_id.should eq("b1") # today: a2 - the keyboard stayed behind
      rebuild(ui)
      ui.type "b2", "k"
      ui.press_title "A"
      ui.focused_id.should eq("a2")
      rebuild(ui)
      ui.press_title "B"
      ui.focused_id.should eq("b2")
      panel(ui, "B").maximized.should be_false
    end

    it "a widget without an id: back on the panel's first stop" do
      ui = scene do |a|
        panel_a(a)
        a.window_panel("B", 330.0, 150.0, 300.0, 260.0, id: "B") do
          a.vstack { a.text_input(id: "b1") { }; a.text_input { } }
        end
      end
      ui.type "b1", "k"
      ui.press "Tab" # today: ac, in A - Tab left B
      idless = keyboard
      idless.should_not be_nil
      idless.not_nil!.id.should be_nil
      ui.press_title "A"
      ui.press_title "B"
      ui.focused_id.should eq("b1") # today: the keyboard stayed in A
    end

    it "Ctrl+Tab rotates the panels and the raised one takes the keyboard; Ctrl+Shift+Tab is the reverse" do
      ui = scene do |a|
        panel_a(a)
        panel_b(a)
        a.window_panel("C", 650.0, 150.0, 300.0, 260.0, id: "C") { a.vstack { a.text_input(id: "c1") { } } }
      end
      ui.type "a2", "k" # A in front, the keyboard on a2
      forward = [] of String?
      3.times { ui.press "Ctrl+Tab"; forward << ui.focused_id }
      forward.should eq(["b1", "c1", "a2"]) # today: a2, a2, a2
      backward = [] of String?
      3.times { ui.press "Ctrl+Shift+Tab"; backward << ui.focused_id }
      backward.should eq(["c1", "b1", "a2"]) # today: the top two swap, the keyboard stays on a2
    end

    it "Ctrl+Tab to a panel with nothing to type into: nobody holds the keyboard" do
      ui = scene do |a|
        a.window_panel("L", 330.0, 150.0, 300.0, 260.0, id: "L") { a.vstack { a.text("just a label") } }
        panel_a(a)
      end
      ui.type "a1", "k"
      ui.press "Ctrl+Tab"
      keyboard.should be_nil # today: a1 kept it
      ui.keys(CrymbleUI::Testing::Keys.typed("x"))
      ui.text("a1").should eq("k") # today: "kx"
      ui.press "Tab"
      keyboard.should be_nil # today: the window's first Tab stop
    end

    it "Ctrl+Tab from the window body enters the one open panel" do
      ui = scene do |a|
        a.hstack { a.text_input(id: "t1") { } }
        panel_a(a)
      end
      ui.type "t1", "k"
      ui.press "Ctrl+Tab"
      ui.focused_id.should eq("a1") # today: t1 - Ctrl+Tab did nothing with one panel
    end

    it "Ctrl+Tab closes an open list first" do
      ui = ab
      ui.press "Enter", on: "ac"
      ui.find("ac").as(CrymbleUI::ComboBox).popup_open?.should be_true # instrument
      ui.press "Ctrl+Tab"
      ui.find("ac").as(CrymbleUI::ComboBox).popup_open?.should be_false # today: left open over the next panel
    end

    {p2_off: "disabled", p2_gone: "gone"}.each do |flag, what|
      it "a remembered widget now #{what}: the panel's home, not its first stop" do
        ui = scene do |a|
          panel_a(a)
          a.window_panel("P", 330.0, 150.0, 300.0, 260.0, id: "P", home_focus: "p3") do
            a.vstack do
              a.text_input(id: "p1") { }
              unless a.flag?(:p2_gone)
                p2 = a.text_input(id: "p2") { }
                p2.enabled = false if a.flag?(:p2_off)
              end
              a.text_input(id: "p3") { }
            end
          end
        end
        ui.type "p2", "k"
        ui.press_title "A"
        ui.app.as(SceneApp).set(flag)
        ui.settle
        ui.press_title "P"
        ui.focused_id.should eq("p3") # today: the keyboard stayed in A
      end
    end
  end

  describe "opening, closing, reopening" do
    it "at launch the front panel holds the keyboard on its home" do
      ui = scene do |a|
        a.window_panel("H", 10.0, 150.0, 300.0, 260.0, id: "H", home_focus: "h2") do
          a.vstack { a.text_input(id: "h1") { }; a.text_input(id: "h2") { } }
        end
      end
      ui.focused_id.should eq("h2") # today: nobody
    end

    it "a panel the app opens takes the keyboard on its first stop" do
      ui = scene do |a|
        a.button("open", id: "open") { a.set(:n_open) }
        panel_a(a)
        if a.flag?(:n_open)
          a.window_panel("N", 650.0, 150.0, 300.0, 260.0, id: "N") do
            a.vstack do
              a.text_input(id: "n1") { }
              a.text_input(id: "n2") { }
            end
          end
        end
      end
      ui.type "a2", "k"
      ui.click "open"
      ui.focused_id.should eq("n1") # today: the open button kept it
      ui.press_title "A"
      ui.focused_id.should eq("a2") # A's last widget
    end

    it "a panel opened by its build focusing a field keeps that field (control)" do
      ui = scene do |a|
        a.button("open", id: "open") { a.set(:n_open) }
        if a.flag?(:n_open)
          a.window_panel("N", 650.0, 150.0, 300.0, 260.0, id: "N") do
            a.vstack do
              a.text_input(id: "n1") { }
              n2 = a.text_input(id: "n2") { }
              unless a.flag?(:focused_once)
                a.flags[:focused_once] = true
                n2.request_focus
              end
            end
          end
        end
      end
      ui.click "open"
      ui.focused_id.should eq("n2")
    end

    it "the first panel opened in a window without one takes the keyboard" do
      ui = scene do |a|
        a.button("open", id: "open") { a.set(:n_open) }
        if a.flag?(:n_open)
          a.window_panel("N", 650.0, 150.0, 300.0, 260.0, id: "N") { a.vstack { a.text_input(id: "n1") { } } }
        end
      end
      ui.click "open"
      ui.focused_id.should eq("n1") # today: the open button kept it, and N was not raised
    end

    it "closing the keyboard's panel by its close button: the panel now in front takes it" do
      ui = ab
      ui.type "a2", "k"
      ui.type "b2", "k" # B in front, A remembers a2
      ui.close_panel "B"
      ui.focused_id.should eq("a2") # today: b2, a widget of the closed panel
      ui.press "Tab"
      ui.focused_id.should_not eq("b1")
    end

    it "a panel removed by its close callback: the panel now in front takes the keyboard" do
      ui = scene { |a| panel_a(a); panel_b(a, closed_callback: true) unless a.flag?(:b_gone) }
      ui.type "a2", "k"
      ui.type "b2", "k"
      ui.close_panel "B"
      ui.focused_id.should eq("a2") # today: nobody
    end

    it "closing a panel BEHIND leaves the keyboard where it is (guard)" do
      ui = ab
      ui.type "b2", "k"
      ui.type "a2", "k" # A in front
      ui.close_panel "B"
      ui.focused_id.should eq("a2")
    end

    it "a reopened panel takes the keyboard back on the widget it last held" do
      ui = scene do |a|
        a.button("reopen", id: "reopen") { a.root.not_nil!.find_by_id("B").as(CrymbleUI::WindowPanel).open }
        panel_a(a)
        panel_b(a)
      end
      ui.type "a2", "k"
      ui.type "b2", "k"
      ui.close_panel "B"
      ui.click "reopen"
      ui.focused_id.should eq("b2") # today: the reopen button kept it
    end

    it "closing a dialog hands the keyboard back without scrolling what it left" do
      ui = scene do |a|
        a.button("dialog", id: "open_d") { a.set(:d_open) }
        a.window_panel("P", 10.0, 150.0, 300.0, 200.0, id: "P") do
          a.scroll_view(id: "sv", max_height: 150.0) do
            a.vstack { 30.times { |i| a.text_input(id: "w#{i}") { } } }
          end
        end
        if a.flag?(:d_open)
          a.window_panel("D", 400.0, 150.0, 300.0, 200.0, id: "D") do
            a.vstack { a.button("close", id: "d_close") { a.set(:d_open, false) } }
          end
        end
      end
      ui.type "w0", "k"
      ui.wheel "sv", -10.0
      offset = ui.find("sv").as(CrymbleUI::ScrollView).scroll_offset
      offset.y.should be > 0.0 # instrument: w0 is scrolled out of view
      ui.click "open_d"
      ui.click "d_close"
      ui.focused_id.should eq("w0") # today: nobody (the close button vanished with the keyboard)
      ui.find("sv").as(CrymbleUI::ScrollView).scroll_offset.should eq(offset)
    end

    it "an id-less panel beside an id'd one is not raised again at every rebuild (guard)" do
      ui = scene do |a|
        panel_a(a)
        a.window_panel("Anon", 330.0, 150.0, 300.0, 260.0) { a.vstack { a.text_input { } } }
      end
      ui.type "a1", "k"
      rebuild(ui)
      rebuild(ui)
      ui.focused_id.should eq("a1")
      front_id(ui).should eq("A") # today: the id-less panel came to the front at every rebuild
    end
  end

  describe "keys go to the keyboard's panel" do
    dialog = ->(a : SceneApp) do
      a.hstack { a.text_input(id: "t1") { }; a.button("body", id: "body_btn") { } }
      a.window_panel("D", 10.0, 150.0, 400.0, 260.0, id: "D") do
        a.vstack do
          a.text_input(id: "d_name") { }
          a.hstack do
            a.button("Ok", shortcut: "Enter", id: "d_ok") { a.log << "ok" }
            a.button("Cancel", id: "d_cancel") { a.log << "cancel" }
            a.button("Close", shortcut: "Escape", id: "d_close") { a.log << "esc" }
            a.button("K", shortcut: "Ctrl+K", id: "d_k") { a.log << "k" }
          end
        end
      end
      nil
    end

    it "Enter on a focused button presses that button, not the panel's Enter" do
      ui = scene { |a| dialog.call(a) }
      ui.type "d_name", "k"
      ui.press "Tab"
      ui.press "Tab"
      ui.focused_id.should eq("d_cancel")
      ui.press "Enter"
      ui.app.as(SceneApp).log.should eq(["cancel"]) # today: ["ok"]
    end

    it "Enter in a text field is the panel's Enter (control)" do
      ui = scene { |a| dialog.call(a) }
      ui.type "d_name", "k"
      ui.press "Enter"
      ui.app.as(SceneApp).log.should eq(["ok"])
    end

    it "from a widget of the window body, no key reaches the panel in front" do
      ui = scene { |a| dialog.call(a) }
      ui.type "t1", "k"
      ui.press "Enter"
      ui.press "Ctrl+K"
      ui.click "body_btn"
      ui.press "Escape"
      ui.app.as(SceneApp).log.should eq([] of String) # today: ok, k, esc
    end
  end
end
