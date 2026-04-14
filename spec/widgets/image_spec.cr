require "../spec_helper"
require "../../src/widgets/image"

describe CrymbleUI::DrawImage do
    it "creates with path, bounds, and default white color" do
        img = CrymbleUI::DrawImage.new("logo.png", CrymbleUI::Rect.new(10, 20, 100, 50))
        img.path.should eq("logo.png")
        img.bounds.x.should eq(10.0)
        img.bounds.y.should eq(20.0)
        img.bounds.width.should eq(100.0)
        img.bounds.height.should eq(50.0)
        img.color.should eq(CrymbleUI::Color.white)
    end

    it "creates with custom tint/alpha color" do
        color = CrymbleUI::Color.new(255, 255, 255, 128)
        img = CrymbleUI::DrawImage.new("logo.png", CrymbleUI::Rect.new(0, 0, 50, 50), color)
        img.color.a.should eq(128)
    end
end

describe CrymbleUI::Image do
    it "produces a DrawImage primitive" do
        widget = CrymbleUI::Image.new("resources/logo.png")
        bounds = CrymbleUI::Rect.new(0, 0, 200, 100)
        primitives = widget.to_primitives(bounds)

        primitives.size.should eq(1)
        primitives[0].should be_a(CrymbleUI::DrawImage)

        img = primitives[0].as(CrymbleUI::DrawImage)
        img.path.should eq("resources/logo.png")
        img.bounds.should eq(bounds)
        img.color.should eq(CrymbleUI::Color.white)
    end

    it "applies tint color" do
        tint = CrymbleUI::Color.new(255, 255, 255, 100)
        widget = CrymbleUI::Image.new("logo.png", tint: tint)
        bounds = CrymbleUI::Rect.new(0, 0, 50, 50)
        primitives = widget.to_primitives(bounds)

        primitives[0].as(CrymbleUI::DrawImage).color.should eq(tint)
    end

    it "measures to fill available constraints" do
        widget = CrymbleUI::Image.new("logo.png")
        constraints = CrymbleUI::BoxConstraints.new(max_width: 300.0, max_height: 200.0)
        size = widget.measure(constraints)
        size.width.should eq(300.0)
        size.height.should eq(200.0)
    end

    it "measures with explicit dimensions" do
        widget = CrymbleUI::Image.new("logo.png", width: 150.0, height: 80.0)
        constraints = CrymbleUI::BoxConstraints.new(max_width: 300.0, max_height: 200.0)
        size = widget.measure(constraints)
        size.width.should eq(150.0)
        size.height.should eq(80.0)
    end
end
