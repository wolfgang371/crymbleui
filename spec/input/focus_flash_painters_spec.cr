require "../spec_helper"
require "../../src/crymble-ui"

# The focus flash costs a frame per toggle (FocusFlashController, every 300 ms), so only a widget that paints it is
# flashed (Widget#paints_focus_flash?). Measured before: a VirtualMatrix holding the keyboard - it draws nothing for
# focus_highlighted - re-rendered its content layer and re-composited every layer three times a second, idle.

private class EveryFocusableApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Focusables", 700, 500) do
      vstack do
        button("Button", id: "button") { }
        checkbox("Checkbox", checked: false, id: "checkbox") { }
        text_input(value: "text", id: "text_input")
        combo_box(["one", "two"], id: "combo_box") { }
        widget(CrymbleUI::MultiComboBox.new(items: ["x", "y"], selected: Set(Int32).new, id: "multi_combo_box"))
        tabs(id: "tabs") { tab("First") { text("page") } }
        tree_node("Section", expanded: false, id: "tree_node") { text("inside") }
        widget(CrymbleUI::VirtualMatrix.new(adapter: MergeableTestAdapter.new(6, 4), id: "grid"))
      end
    end
  end
end

# The classes that can hold the keyboard, read from the source: a class that defines focusable? (unless as a plain
# `false`) or sets @focusable = true. A focusable widget added later fails the sweep below until it is in
# EveryFocusableApp - except a subclass that inherits focusable? without defining it, which this scan cannot see.
private def focusable_classes_in_source : Set(String)
  found = Set(String).new
  src_glob("src/widgets/**/*.cr").each do |file|
    current = nil
    lines = File.read_lines(file)
    lines.each_with_index do |line, i|
      if m = line.match(/^\s*(?:private\s+|abstract\s+)*class (\w+)/)
        current = m[1]
      elsif current && (line.includes?("@focusable = true") ||
                        (line =~ /def focusable\? : Bool/ && lines[i + 1]?.try(&.strip) != "false"))
        found << current
      end
    end
  end
  found
end

private def lr
  CrymbleUI::LayerRenderer
end

describe "the focus flash" do
  it "is painted exactly by the widgets that say so, for every focusable widget class" do
    app = EveryFocusableApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(700, 500)
    renderer.settle_rendering(app)
    focusables = app.find_all(&.focusable?).uniq(&.class)
    focusables.map(&.class.name.split("::").last).to_set.should eq focusable_classes_in_source
    focusables.each do |w|
      w.enabled?.should be_true # a disabled Button draws no flash either - the comparison needs the live state
      w.focus_highlighted = true
      on = w.to_primitives(w.bounds).map(&.inspect)
      w.focus_highlighted = false
      off = w.to_primitives(w.bounds).map(&.inspect)
      (on != off).should eq(w.paints_focus_flash?), "#{w.class}: draws the flash #{on != off}, says #{w.paints_focus_flash?}"
    end
  end

  it "costs a grid holding the keyboard no frames - only its cursor flash renders" do
    app = EveryFocusableApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(700, 500)
    renderer.settle_rendering(app)
    grid = app.find("grid").not_nil!
    CrymbleUI::Widget.focus_manager.focus(grid)
    renderer.settle_rendering(app)

    now = Time.instant
    content_renders = 0
    frames = 0
    20.times do # 2 s in 100 ms steps
      now += 100.milliseconds
      renderer.scheduler.run_expired_timers(now)
      lr.reset_frame_counters
      renderer.render_frame(app)
      ids = lr.rendered_layer_ids
      frames += 1 unless ids.empty?
      content_renders += ids.count(&.starts_with?("matrix_content"))
    end
    cursor_toggles = 2000 // CrymbleUI::VirtualMatrix::CURSOR_FLASH_MS
    content_renders.should eq 0
    frames.should eq cursor_toggles
  end
end
