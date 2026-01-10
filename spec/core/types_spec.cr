require "../spec_helper"

describe CrymbleUI::Vec2 do
    describe ".new" do
        it "creates a vector with float coordinates" do
            v = CrymbleUI::Vec2.new(10.5, 20.5)
            v.x.should eq(10.5)
            v.y.should eq(20.5)
        end

        it "creates a vector with integer coordinates" do
            v = CrymbleUI::Vec2.new(10, 20)
            v.x.should eq(10.0)
            v.y.should eq(20.0)
        end
    end

    describe "+" do
        it "adds two vectors" do
            v1 = CrymbleUI::Vec2.new(1.0, 2.0)
            v2 = CrymbleUI::Vec2.new(3.0, 4.0)
            result = v1 + v2
            result.x.should eq(4.0)
            result.y.should eq(6.0)
        end
    end

    describe "-" do
        it "subtracts two vectors" do
            v1 = CrymbleUI::Vec2.new(5.0, 6.0)
            v2 = CrymbleUI::Vec2.new(2.0, 1.0)
            result = v1 - v2
            result.x.should eq(3.0)
            result.y.should eq(5.0)
        end
    end

    describe "*" do
        it "multiplies vector by scalar" do
            v = CrymbleUI::Vec2.new(2.0, 3.0)
            result = v * 2.0
            result.x.should eq(4.0)
            result.y.should eq(6.0)
        end
    end

    describe "#distance_to" do
        it "calculates distance between vectors" do
            v1 = CrymbleUI::Vec2.new(0.0, 0.0)
            v2 = CrymbleUI::Vec2.new(3.0, 4.0)
            v1.distance_to(v2).should eq(5.0)
        end
    end

    describe ".zero" do
        it "creates zero vector" do
            v = CrymbleUI::Vec2.zero
            v.x.should eq(0.0)
            v.y.should eq(0.0)
        end
    end
end

describe CrymbleUI::Size do
    describe ".new" do
        it "creates size with float dimensions" do
            s = CrymbleUI::Size.new(100.5, 200.5)
            s.width.should eq(100.5)
            s.height.should eq(200.5)
        end

        it "creates size with integer dimensions" do
            s = CrymbleUI::Size.new(100, 200)
            s.width.should eq(100.0)
            s.height.should eq(200.0)
        end
    end

    describe "#area" do
        it "calculates area" do
            s = CrymbleUI::Size.new(10.0, 20.0)
            s.area.should eq(200.0)
        end
    end

    describe "#aspect_ratio" do
        it "calculates aspect ratio" do
            s = CrymbleUI::Size.new(16.0, 9.0)
            s.aspect_ratio.should be_close(1.777, 0.001)
        end
    end

    describe "#is_empty?" do
        it "returns true for zero or negative dimensions" do
            CrymbleUI::Size.new(0.0, 10.0).is_empty?.should be_true
            CrymbleUI::Size.new(10.0, 0.0).is_empty?.should be_true
            CrymbleUI::Size.new(-5.0, 10.0).is_empty?.should be_true
        end

        it "returns false for positive dimensions" do
            CrymbleUI::Size.new(10.0, 20.0).is_empty?.should be_false
        end
    end

    describe "#contains" do
        it "returns true if size can contain another size" do
            s1 = CrymbleUI::Size.new(100.0, 100.0)
            s2 = CrymbleUI::Size.new(50.0, 50.0)
            s1.contains(s2).should be_true
        end

        it "returns false if size cannot contain another size" do
            s1 = CrymbleUI::Size.new(50.0, 50.0)
            s2 = CrymbleUI::Size.new(100.0, 100.0)
            s1.contains(s2).should be_false
        end
    end
end

describe CrymbleUI::Rect do
    describe ".new" do
        it "creates rect from position and size" do
            pos = CrymbleUI::Vec2.new(10.0, 20.0)
            size = CrymbleUI::Size.new(100.0, 200.0)
            r = CrymbleUI::Rect.new(pos, size)
            r.x.should eq(10.0)
            r.y.should eq(20.0)
            r.width.should eq(100.0)
            r.height.should eq(200.0)
        end

        it "creates rect from coordinates" do
            r = CrymbleUI::Rect.new(10.0, 20.0, 100.0, 200.0)
            r.x.should eq(10.0)
            r.y.should eq(20.0)
            r.width.should eq(100.0)
            r.height.should eq(200.0)
        end
    end

    describe "#left, #top, #right, #bottom" do
        it "returns correct edge positions" do
            r = CrymbleUI::Rect.new(10.0, 20.0, 100.0, 200.0)
            r.left.should eq(10.0)
            r.top.should eq(20.0)
            r.right.should eq(110.0)
            r.bottom.should eq(220.0)
        end
    end

    describe "#center" do
        it "returns center point" do
            r = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 200.0)
            center = r.center
            center.x.should eq(50.0)
            center.y.should eq(100.0)
        end
    end

    describe "#contains_point" do
        it "returns true for point inside rect" do
            r = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0)
            r.contains_point(CrymbleUI::Vec2.new(50.0, 50.0)).should be_true
        end

        it "returns false for point outside rect" do
            r = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0)
            r.contains_point(CrymbleUI::Vec2.new(150.0, 150.0)).should be_false
        end
    end

    describe "#intersects" do
        it "returns true for overlapping rects" do
            r1 = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0)
            r2 = CrymbleUI::Rect.new(50.0, 50.0, 100.0, 100.0)
            r1.intersects(r2).should be_true
        end

        it "returns false for non-overlapping rects" do
            r1 = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0)
            r2 = CrymbleUI::Rect.new(200.0, 200.0, 100.0, 100.0)
            r1.intersects(r2).should be_false
        end
    end
end

describe CrymbleUI::Color do
    describe ".new" do
        it "creates color from RGBA values" do
            c = CrymbleUI::Color.new(255_u8, 128_u8, 0_u8, 255_u8)
            c.r.should eq(255)
            c.g.should eq(128)
            c.b.should eq(0)
            c.a.should eq(255)
        end

        it "defaults alpha to 255" do
            c = CrymbleUI::Color.new(255_u8, 128_u8, 0_u8)
            c.a.should eq(255)
        end
    end

    describe ".from_hex" do
        it "parses 6-digit hex" do
            c = CrymbleUI::Color.from_hex("#FF8000")
            c.r.should eq(255)
            c.g.should eq(128)
            c.b.should eq(0)
            c.a.should eq(255)
        end

        it "parses 8-digit hex with alpha" do
            c = CrymbleUI::Color.from_hex("#FF800080")
            c.r.should eq(255)
            c.g.should eq(128)
            c.b.should eq(0)
            c.a.should eq(128)
        end

        it "parses hex without # prefix" do
            c = CrymbleUI::Color.from_hex("FF8000")
            c.r.should eq(255)
            c.g.should eq(128)
            c.b.should eq(0)
        end
    end

    describe "#to_hex" do
        it "converts to hex without alpha if opaque" do
            c = CrymbleUI::Color.new(255, 128, 0)
            c.to_hex.should eq("#FF8000")
        end

        it "includes alpha if not opaque" do
            c = CrymbleUI::Color.new(255, 128, 0, 128)
            c.to_hex.should eq("#FF800080")
        end
    end

    describe ".from_floats" do
        it "creates color from normalized values" do
            c = CrymbleUI::Color.from_floats(1.0, 0.5, 0.0)
            c.r.should eq(255)
            c.g.should eq(127)
            c.b.should eq(0)
        end
    end

    describe "common colors" do
        it "provides predefined colors" do
            CrymbleUI::Color.black.should eq(CrymbleUI::Color.new(0, 0, 0))
            CrymbleUI::Color.white.should eq(CrymbleUI::Color.new(255, 255, 255))
            CrymbleUI::Color.red.should eq(CrymbleUI::Color.new(255, 0, 0))
        end
    end

    describe "*" do
        it "multiplies RGB channels by scalar (clamped)" do
            c = CrymbleUI::Color.new(100, 80, 60, 255)
            result = c * 1.5
            result.r.should eq(150)
            result.g.should eq(120)
            result.b.should eq(90)
            result.a.should eq(255)  # Alpha unchanged
        end

        it "clamps RGB channels to 255" do
            c = CrymbleUI::Color.new(200, 200, 200, 255)
            result = c * 2.0
            result.r.should eq(255)
            result.g.should eq(255)
            result.b.should eq(255)
        end

        it "clamps RGB channels to 0" do
            c = CrymbleUI::Color.new(100, 100, 100, 255)
            result = c * 0.0
            result.r.should eq(0)
            result.g.should eq(0)
            result.b.should eq(0)
        end
    end

    describe "#to_hsv" do
        it "converts red to HSV" do
            c = CrymbleUI::Color.new(255, 0, 0, 255)
            hsv = c.to_hsv
            hsv[:h].should be_close(0.0, 0.1)
            hsv[:s].should be_close(1.0, 0.01)
            hsv[:v].should be_close(1.0, 0.01)
            hsv[:a].should eq(255)
        end

        it "converts green to HSV" do
            c = CrymbleUI::Color.new(0, 255, 0, 255)
            hsv = c.to_hsv
            hsv[:h].should be_close(120.0, 0.1)
            hsv[:s].should be_close(1.0, 0.01)
            hsv[:v].should be_close(1.0, 0.01)
        end

        it "converts blue to HSV" do
            c = CrymbleUI::Color.new(0, 0, 255, 255)
            hsv = c.to_hsv
            hsv[:h].should be_close(240.0, 0.1)
            hsv[:s].should be_close(1.0, 0.01)
            hsv[:v].should be_close(1.0, 0.01)
        end

        it "converts gray to HSV" do
            c = CrymbleUI::Color.new(128, 128, 128, 255)
            hsv = c.to_hsv
            hsv[:s].should be_close(0.0, 0.01)  # No saturation for gray
            hsv[:v].should be_close(0.502, 0.01)
        end
    end

    describe ".from_hsv" do
        it "creates color from HSV tuple" do
            hsv = {h: 0.0, s: 1.0, v: 1.0, a: 255_u8}
            c = CrymbleUI::Color.from_hsv(hsv)
            c.r.should eq(255)
            c.g.should eq(0)
            c.b.should eq(0)
            c.a.should eq(255)
        end

        it "creates color from HSV parameters" do
            c = CrymbleUI::Color.from_hsv(120.0, 1.0, 1.0, 255_u8)
            c.r.should eq(0)
            c.g.should eq(255)
            c.b.should eq(0)
        end

        it "wraps hue around 360" do
            c1 = CrymbleUI::Color.from_hsv(0.0, 1.0, 1.0)
            c2 = CrymbleUI::Color.from_hsv(360.0, 1.0, 1.0)
            c1.should eq(c2)
        end

        it "clamps saturation to 0-1" do
            c = CrymbleUI::Color.from_hsv(0.0, 2.0, 1.0)
            c.r.should eq(255)
            c.g.should eq(0)
            c.b.should eq(0)
        end

        it "clamps value to 0-1" do
            c = CrymbleUI::Color.from_hsv(0.0, 0.0, 2.0)
            c.r.should eq(255)
            c.g.should eq(255)
            c.b.should eq(255)
        end
    end

    describe "HSV roundtrip" do
        it "converts to HSV and back preserving color" do
            original = CrymbleUI::Color.new(100, 150, 200, 255)
            hsv = original.to_hsv
            restored = CrymbleUI::Color.from_hsv(hsv)
            # Allow small rounding errors
            (original.r - restored.r).abs.should be <= 1
            (original.g - restored.g).abs.should be <= 1
            (original.b - restored.b).abs.should be <= 1
            restored.a.should eq(original.a)
        end
    end

    describe "#lighten" do
        it "increases brightness" do
            c = CrymbleUI::Color.new(100, 100, 100, 255)
            lighter = c.lighten(0.2)
            lighter.r.should be > c.r
            lighter.g.should be > c.g
            lighter.b.should be > c.b
        end
    end

    describe "#darken" do
        it "decreases brightness" do
            c = CrymbleUI::Color.new(150, 150, 150, 255)
            darker = c.darken(0.2)
            darker.r.should be < c.r
            darker.g.should be < c.g
            darker.b.should be < c.b
        end
    end

    describe "#saturate" do
        it "increases saturation" do
            c = CrymbleUI::Color.new(150, 100, 100, 255)
            saturated = c.saturate(0.2)
            hsv1 = c.to_hsv
            hsv2 = saturated.to_hsv
            hsv2[:s].should be > hsv1[:s]
        end
    end

    describe "#desaturate" do
        it "decreases saturation" do
            c = CrymbleUI::Color.new(150, 100, 100, 255)
            desaturated = c.desaturate(0.2)
            hsv1 = c.to_hsv
            hsv2 = desaturated.to_hsv
            hsv2[:s].should be < hsv1[:s]
        end
    end

    describe "#rotate_hue" do
        it "rotates hue by degrees" do
            c = CrymbleUI::Color.new(255, 0, 0, 255)  # Red (hue 0)
            rotated = c.rotate_hue(120.0)  # Should become green
            hsv = rotated.to_hsv
            hsv[:h].should be_close(120.0, 0.1)
        end
    end
end

describe CrymbleUI::BoxConstraints do
    describe ".tight" do
        it "creates tight constraints" do
            size = CrymbleUI::Size.new(100.0, 200.0)
            c = CrymbleUI::BoxConstraints.tight(size)
            c.min_width.should eq(100.0)
            c.max_width.should eq(100.0)
            c.min_height.should eq(200.0)
            c.max_height.should eq(200.0)
            c.is_tight?.should be_true
        end
    end

    describe ".loose" do
        it "creates loose constraints" do
            size = CrymbleUI::Size.new(100.0, 200.0)
            c = CrymbleUI::BoxConstraints.loose(size)
            c.min_width.should eq(0.0)
            c.max_width.should eq(100.0)
            c.min_height.should eq(0.0)
            c.max_height.should eq(200.0)
        end
    end

    describe "#constrain" do
        it "constrains size within bounds" do
            c = CrymbleUI::BoxConstraints.new(min_width: 50.0, max_width: 100.0, min_height: 50.0, max_height: 100.0)

            # Too small
            result = c.constrain(CrymbleUI::Size.new(10.0, 10.0))
            result.width.should eq(50.0)
            result.height.should eq(50.0)

            # Too large
            result = c.constrain(CrymbleUI::Size.new(200.0, 200.0))
            result.width.should eq(100.0)
            result.height.should eq(100.0)

            # Within bounds
            result = c.constrain(CrymbleUI::Size.new(75.0, 75.0))
            result.width.should eq(75.0)
            result.height.should eq(75.0)
        end
    end

    describe "#tighten" do
        it "tightens constraints to specific values" do
            c = CrymbleUI::BoxConstraints.new(min_width: 0.0, max_width: 200.0, min_height: 0.0, max_height: 200.0)
            tight = c.tighten(width: 100.0, height: 100.0)
            tight.min_width.should eq(100.0)
            tight.max_width.should eq(100.0)
            tight.min_height.should eq(100.0)
            tight.max_height.should eq(100.0)
        end
    end

    describe "#loosen" do
        it "removes minimum constraints" do
            c = CrymbleUI::BoxConstraints.new(min_width: 50.0, max_width: 100.0, min_height: 50.0, max_height: 100.0)
            loose = c.loosen
            loose.min_width.should eq(0.0)
            loose.max_width.should eq(100.0)
            loose.min_height.should eq(0.0)
            loose.max_height.should eq(100.0)
        end
    end

    describe "#is_bounded?" do
        it "returns true when dimensions are finite" do
            c = CrymbleUI::BoxConstraints.new(max_width: 100.0, max_height: 100.0)
            c.is_bounded?.should be_true
        end

        it "returns false when dimensions are infinite" do
            c = CrymbleUI::BoxConstraints.new
            c.is_bounded?.should be_false
        end
    end
end
