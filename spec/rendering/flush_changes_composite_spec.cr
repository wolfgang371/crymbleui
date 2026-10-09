require "../spec_helper"
require "../../src/testing/test_renderer"

# AN OWNER'S FLUSH MAY CHANGE WHAT THE FRAME COMPOSITES - move a layer, attach one (a grid scrolling cells that own
# layers into view does both). The render loop decides occlusion before it starts, so each layer is re-asked at its
# turn, the frame's list is re-collected when the composite set changed, and a layer still skipped as covered is
# re-asked once the flushes are done. Here layer owners whose flush is scripted: opaque boxes on a window.

private OLD   = CrymbleUI::Color.new(200, 0, 0, 255)
private NEW   = CrymbleUI::Color.new(0, 200, 0, 255)
private COVER = CrymbleUI::Color.new(0, 0, 200, 255)

# An opaque layer owner (it covers what is under it) whose next flush runs `flush`.
class FccBox < CrymbleUI::LayerBox
  property flush : Proc(Nil)? = nil

  def initialize(x : Float64, y : Float64, w : Float64, h : Float64, z : Int32, @fill : CrymbleUI::Color, id : String)
    super(x, y, w, h, z_index: z, id: id)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    super
    layer.not_nil!.background_color = @fill # opaque: an occluder
  end

  def pre_render_flush
    if job = @flush
      @flush = nil
      job.call
    end
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @fill).as(CrymbleUI::DrawPrimitive)]
  end

  def recolour(@fill : CrymbleUI::Color) : Nil
    layer.try(&.background_color = @fill)
    mark_needs_render
  end

  # Moves it, laid out at once: what a deferred layout in a flush does.
  def move_to(x : Float64) : Nil
    self.x = x
    layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(600.0, 400.0)), CrymbleUI::Vec2.zero)
  end
end

class FccApp < CrymbleUI::App
  def initialize(@boxes : Array(FccBox))
    super()
  end

  def build : CrymbleUI::Widget
    CrymbleUI::Window.new("W", 600, 400).tap { |window| @boxes.each { |box| window.add_child(box) } }
  end
end

private def fcc(*boxes : FccBox) : {CrymbleUI::Testing::TestRenderer, FccApp}
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
  app = FccApp.new(boxes.to_a)
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer.settle_rendering(app)
  {renderer, app}
end

private def pixel(renderer, box : FccBox) : CrymbleUI::Color?
  at = box.absolute_bounds.center
  renderer.backend.get_pixel(at.x.to_i, at.y.to_i)
end

describe "a flush that changes what the frame composites" do
  # The occluder flushes AFTER the covered layer's turn (it sorts above it): only the re-ask once the flushes are
  # done can see the layer is uncovered.
  it "a layer uncovered by a later layer's flush is painted that frame" do
    under = FccBox.new(50.0, 50.0, 60.0, 30.0, 1, OLD, "under")
    cover = FccBox.new(40.0, 40.0, 100.0, 60.0, 2, COVER, "cover")
    renderer, app = fcc(under, cover)
    pixel(renderer, under).should eq(COVER) # instrument: covered
    under.recolour(NEW)
    cover.flush = -> { cover.move_to(300.0) }
    cover.recolour(COVER) # it renders this frame, so its flush runs
    CrymbleUI::LayerRenderer.reset_frame_counters
    renderer.render_frame(app)
    (CrymbleUI::LayerRenderer.frame_layers_occluded > 0).should be_true # instrument: decided covered before the loop
    pixel(renderer, under).should eq(NEW)
  end

  # An earlier owner's flush moves the occluder BEFORE the covered layer's turn: re-asked at its turn, the layer is
  # painted IN ORDER - before the layers after it, which a flush of its own may move (the order law).
  it "a layer uncovered by an earlier layer's flush is painted at its turn" do
    mover = FccBox.new(400.0, 300.0, 20.0, 20.0, 1, OLD, "mover")
    under = FccBox.new(50.0, 50.0, 60.0, 30.0, 2, OLD, "under")
    cover = FccBox.new(40.0, 40.0, 100.0, 60.0, 3, COVER, "cover")
    renderer, app = fcc(mover, under, cover)
    pixel(renderer, under).should eq(COVER) # instrument: covered
    under.recolour(NEW)
    cover.recolour(COVER)
    mover.flush = -> { cover.move_to(300.0) }
    mover.recolour(OLD)
    CrymbleUI::LayerRenderer.reset_frame_counters
    renderer.render_frame(app)
    (CrymbleUI::LayerRenderer.frame_layers_occluded > 0).should be_true # instrument: decided covered before the loop
    pixel(renderer, under).should eq(NEW)
    ids = CrymbleUI::LayerRenderer.rendered_layer_ids
    (ids.index!(under.layer.not_nil!.id) < ids.index!(cover.layer.not_nil!.id)).should be_true
  end

  # A flush ATTACHES a layer owner (as a grid attaches cells) under an opaque layer: the re-collected frame decides
  # occlusion again, so the new layer - covered - is not rendered.
  it "a layer a flush attaches under an opaque layer is not rendered" do
    spawner = FccBox.new(400.0, 300.0, 20.0, 20.0, 1, OLD, "spawner")
    cover = FccBox.new(40.0, 40.0, 100.0, 60.0, 3, COVER, "cover")
    renderer, app = fcc(spawner, cover)
    born = FccBox.new(50.0, 50.0, 60.0, 30.0, 2, NEW, "born")
    spawner.flush = -> do
      app.root.not_nil!.add_child(born)
      born.layout(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(600.0, 400.0)), CrymbleUI::Vec2.zero)
      CrymbleUI::Layer.reorder! # the composite set changed, as a grid's attach announces it
    end
    spawner.recolour(OLD)
    CrymbleUI::LayerRenderer.reset_frame_counters
    renderer.render_frame(app)
    CrymbleUI::LayerRenderer.frame_in_loop_recollect_count.should eq(1) # instrument: collected in the loop
    renderer.cached_layers.not_nil!.includes?(born.layer.not_nil!).should be_true
    CrymbleUI::LayerRenderer.rendered_layer_ids.includes?(born.layer.not_nil!.id).should be_false
    born.layer.not_nil!.backend.should_not be_nil # collected, so prepared like every layer of the frame
    pixel(renderer, born).should eq(COVER)
  end
end
