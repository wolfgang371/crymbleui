require "../spec_helper"
require "../../src/input/event_batch"
require "../../src/testing/keys"

# A batch ends at the first event that raises the input barrier (here: a requested rebuild; a
# matrix's invalidate_all! raises it too, see virtual_matrix_batch_text_spec): the events queued
# behind it must be dispatched against the state that work produces, not the state it replaces. embrace's
# spec/gui/input_batch_spec.cr is the field case (Tabs queued behind Ctrl+R).

describe CrymbleUI::EventBatch do
  it "stops at the event that requests a rebuild and leaves the rest queued" do
    app = TestApp.new
    queue = Deque(LibCSFML::Event).new("abcd".chars.map { |c| CrymbleUI::Testing::Keys.text(c) })
    seen = [] of Char
    drained = CrymbleUI::EventBatch.drain(app, -> { queue.shift? }) do |event|
      char = event.text.unicode.chr
      seen << char
      app.request_rebuild if char == 'b'
    end

    drained.should eq(2)
    seen.should eq(['a', 'b'])
    queue.size.should eq(2) # 'c' and 'd' wait for the next iteration
  end

  it "drains everything when nothing requests a rebuild" do
    app = TestApp.new
    queue = Deque(LibCSFML::Event).new("abcd".chars.map { |c| CrymbleUI::Testing::Keys.text(c) })
    CrymbleUI::EventBatch.drain(app, -> { queue.shift? }) { }.should eq(4)
    queue.should be_empty
  end

  it "waits on a widget's barrier until the next frame lifts it" do
    app = TestApp.new
    queue = Deque(LibCSFML::Event).new("abc".chars.map { |c| CrymbleUI::Testing::Keys.text(c) })
    handle = ->(event : LibCSFML::Event) { app.request_frame_before_input if event.text.unicode.chr == 'a' }
    CrymbleUI::EventBatch.drain(app, -> { queue.shift? }) { |e| handle.call(e) }.should eq(1)
    CrymbleUI::EventBatch.drain(app, -> { queue.shift? }) { |e| handle.call(e) }.should eq(0) # no frame yet

    app.prepare_layout(CrymbleUI::Size.new(100.0, 100.0)) # what every frame runs
    CrymbleUI::EventBatch.drain(app, -> { queue.shift? }) { |e| handle.call(e) }.should eq(2)
  end

  # A rebuild that only refreshes other views of the data (embrace: a per-cell write) is applied at
  # the end of the batch, like any rebuild, but does not stop it; a blocking request in the same
  # batch still does.
  it "lets a non-blocking rebuild wait for the end of the batch" do
    app = TestApp.new
    queue = Deque(LibCSFML::Event).new("abcd".chars.map { |c| CrymbleUI::Testing::Keys.text(c) })
    drained = CrymbleUI::EventBatch.drain(app, -> { queue.shift? }) do |event|
      case event.text.unicode.chr
      when 'a', 'b' then app.request_rebuild(blocks_input: false)
      when 'c'      then app.request_rebuild
      end
    end

    drained.should eq(3) # 'a' and 'b' did not stop it; 'c' did
    app.needs_rebuild?.should be_true
    queue.size.should eq(1)
  end
end
