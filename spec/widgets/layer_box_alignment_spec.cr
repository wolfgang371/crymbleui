require "../spec_helper"
require "../../src/widgets/layer_box"

describe "LayerBox alignment" do
    describe "Alignment enum" do
        it "has all 9 alignment values plus None" do
            CrymbleUI::Alignment::None.should be_a(CrymbleUI::Alignment)
            CrymbleUI::Alignment::TopLeft.should be_a(CrymbleUI::Alignment)
            CrymbleUI::Alignment::TopCenter.should be_a(CrymbleUI::Alignment)
            CrymbleUI::Alignment::TopRight.should be_a(CrymbleUI::Alignment)
            CrymbleUI::Alignment::MiddleLeft.should be_a(CrymbleUI::Alignment)
            CrymbleUI::Alignment::Center.should be_a(CrymbleUI::Alignment)
            CrymbleUI::Alignment::MiddleRight.should be_a(CrymbleUI::Alignment)
            CrymbleUI::Alignment::BottomLeft.should be_a(CrymbleUI::Alignment)
            CrymbleUI::Alignment::BottomCenter.should be_a(CrymbleUI::Alignment)
            CrymbleUI::Alignment::BottomRight.should be_a(CrymbleUI::Alignment)
        end
    end

    describe "Percent struct" do
        it "stores percentage as 0.0-1.0 value" do
            pct = CrymbleUI::Percent.of(50)
            pct.value.should eq(0.5)
        end

        it "handles 100%" do
            pct = CrymbleUI::Percent.of(100)
            pct.value.should eq(1.0)
        end

        it "handles fractional percentages" do
            pct = CrymbleUI::Percent.of(33.33)
            pct.value.should be_close(0.3333, 0.0001)
        end
    end

    describe "#constrain_to_window_bounds" do
        window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)

        describe "with Alignment::None" do
            it "does not change position" do
                box = CrymbleUI::LayerBox.new(100.0, 100.0, 200.0, 150.0, alignment: CrymbleUI::Alignment::None)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(100.0)
                box.y.should eq(100.0)
            end
        end

        describe "corner alignments" do
            it "positions TopLeft with margin" do
                box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                    alignment: CrymbleUI::Alignment::TopLeft, margin: 10.0)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(10.0)
                box.y.should eq(10.0)
            end

            it "positions TopRight with margin" do
                box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                    alignment: CrymbleUI::Alignment::TopRight, margin: 10.0)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(690.0)  # 800 - 100 - 10
                box.y.should eq(10.0)
            end

            it "positions BottomLeft with margin" do
                box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                    alignment: CrymbleUI::Alignment::BottomLeft, margin: 10.0)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(10.0)
                box.y.should eq(540.0)  # 600 - 50 - 10
            end

            it "positions BottomRight with margin" do
                box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                    alignment: CrymbleUI::Alignment::BottomRight, margin: 10.0)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(690.0)  # 800 - 100 - 10
                box.y.should eq(540.0)  # 600 - 50 - 10
            end
        end

        describe "center alignments" do
            it "positions TopCenter" do
                box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                    alignment: CrymbleUI::Alignment::TopCenter, margin: 10.0)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(350.0)  # (800 - 100) / 2
                box.y.should eq(10.0)
            end

            it "positions MiddleLeft" do
                box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                    alignment: CrymbleUI::Alignment::MiddleLeft, margin: 10.0)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(10.0)
                box.y.should eq(275.0)  # (600 - 50) / 2
            end

            it "positions Center" do
                box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                    alignment: CrymbleUI::Alignment::Center)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(350.0)  # (800 - 100) / 2
                box.y.should eq(275.0)  # (600 - 50) / 2
            end

            it "positions MiddleRight" do
                box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                    alignment: CrymbleUI::Alignment::MiddleRight, margin: 10.0)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(690.0)  # 800 - 100 - 10
                box.y.should eq(275.0)  # (600 - 50) / 2
            end

            it "positions BottomCenter" do
                box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                    alignment: CrymbleUI::Alignment::BottomCenter, margin: 10.0)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(350.0)  # (800 - 100) / 2
                box.y.should eq(540.0)  # 600 - 50 - 10
            end
        end

        describe "with zero margin" do
            it "positions TopRight flush with edge" do
                box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                    alignment: CrymbleUI::Alignment::TopRight, margin: 0.0)
                box.constrain_to_window_bounds(window_bounds)

                box.x.should eq(700.0)  # 800 - 100
                box.y.should eq(0.0)
            end
        end
    end

    describe "percentage sizing" do
        window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)

        it "calculates width as percentage of window" do
            box = CrymbleUI::LayerBox.new(0.0, 0.0, nil, 50.0,
                alignment: CrymbleUI::Alignment::Center,
                width_spec: CrymbleUI::Percent.of(50))
            box.constrain_to_window_bounds(window_bounds)

            box.bounds.width.should eq(400.0)  # 50% of 800
        end

        it "calculates height as percentage of window" do
            box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, nil,
                alignment: CrymbleUI::Alignment::Center,
                height_spec: CrymbleUI::Percent.of(25))
            box.constrain_to_window_bounds(window_bounds)

            box.bounds.height.should eq(150.0)  # 25% of 600
        end

        it "calculates both width and height as percentages" do
            box = CrymbleUI::LayerBox.new(0.0, 0.0, nil, nil,
                alignment: CrymbleUI::Alignment::BottomCenter,
                width_spec: CrymbleUI::Percent.of(80),
                height_spec: CrymbleUI::Percent.of(10),
                margin: 20.0)
            box.constrain_to_window_bounds(window_bounds)

            box.bounds.width.should eq(640.0)   # 80% of 800
            box.bounds.height.should eq(60.0)   # 10% of 600
            box.x.should eq(80.0)               # (800 - 640) / 2
            box.y.should eq(520.0)              # 600 - 60 - 20
        end

        it "positions percentage-sized widget correctly at TopRight" do
            box = CrymbleUI::LayerBox.new(0.0, 0.0, nil, nil,
                alignment: CrymbleUI::Alignment::TopRight,
                width_spec: CrymbleUI::Percent.of(20),
                height_spec: CrymbleUI::Percent.of(5),
                margin: 10.0)
            box.constrain_to_window_bounds(window_bounds)

            box.bounds.width.should eq(160.0)   # 20% of 800
            box.bounds.height.should eq(30.0)   # 5% of 600
            box.x.should eq(630.0)              # 800 - 160 - 10
            box.y.should eq(10.0)
        end
    end

    describe "window resize handling" do
        it "repositions on window resize" do
            box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                alignment: CrymbleUI::Alignment::TopRight, margin: 10.0)

            # Initial window size
            box.constrain_to_window_bounds(CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0))
            box.x.should eq(690.0)

            # Window resized smaller
            box.constrain_to_window_bounds(CrymbleUI::Rect.new(0.0, 0.0, 640.0, 480.0))
            box.x.should eq(530.0)  # 640 - 100 - 10
            box.y.should eq(10.0)
        end

        it "recalculates percentage sizes on window resize" do
            box = CrymbleUI::LayerBox.new(0.0, 0.0, nil, nil,
                alignment: CrymbleUI::Alignment::Center,
                width_spec: CrymbleUI::Percent.of(50),
                height_spec: CrymbleUI::Percent.of(50))

            # Initial window size
            box.constrain_to_window_bounds(CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0))
            box.bounds.width.should eq(400.0)
            box.bounds.height.should eq(300.0)

            # Window resized
            box.constrain_to_window_bounds(CrymbleUI::Rect.new(0.0, 0.0, 1000.0, 800.0))
            box.bounds.width.should eq(500.0)   # 50% of 1000
            box.bounds.height.should eq(400.0)  # 50% of 800
        end
    end

    describe "layer bounds sync" do
        it "updates layer bounds when alignment recalculates" do
            box = CrymbleUI::LayerBox.new(0.0, 0.0, 100.0, 50.0,
                alignment: CrymbleUI::Alignment::TopRight, margin: 10.0)
            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)

            box.constrain_to_window_bounds(window_bounds)

            layer = box.layer.not_nil!
            layer.bounds.x.should eq(690.0)
            layer.bounds.y.should eq(10.0)
            layer.bounds.width.should eq(100.0)
            layer.bounds.height.should eq(50.0)
        end
    end

    describe "default alignment" do
        it "defaults to Alignment::None" do
            box = CrymbleUI::LayerBox.new(100.0, 100.0, 200.0, 150.0)
            box.alignment.should eq(CrymbleUI::Alignment::None)
        end

        it "maintains backward compatibility with explicit x, y" do
            box = CrymbleUI::LayerBox.new(100.0, 100.0, 200.0, 150.0)
            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)

            # Should not change position since alignment is None
            box.constrain_to_window_bounds(window_bounds)
            box.x.should eq(100.0)
            box.y.should eq(100.0)
        end
    end

    describe "auto-sizing from content" do
        it "uses child's natural size when no explicit size given" do
            # Create box with NO explicit size - this is the bug case!
            box = CrymbleUI::LayerBox.new(0.0, 0.0, nil, nil,
                alignment: CrymbleUI::Alignment::TopRight, margin: 10.0)

            # Add child with known size (100x50)
            child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
            box.add_child(child)

            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)
            box.constrain_to_window_bounds(window_bounds)

            # Should use child's size (100x50), not window size (800x600)
            box.bounds.width.should eq(100.0)
            box.bounds.height.should eq(50.0)
            box.x.should eq(690.0)  # 800 - 100 - 10
            box.y.should eq(10.0)
        end

        it "positions TopRight correctly with auto-sized content" do
            box = CrymbleUI::LayerBox.new(0.0, 0.0, nil, nil,
                alignment: CrymbleUI::Alignment::TopRight, margin: 20.0)

            # Smaller child (50x30)
            child = TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 30.0))
            box.add_child(child)

            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)
            box.constrain_to_window_bounds(window_bounds)

            box.bounds.width.should eq(50.0)
            box.bounds.height.should eq(30.0)
            box.x.should eq(730.0)  # 800 - 50 - 20
            box.y.should eq(20.0)
        end

        it "positions Center correctly with auto-sized content" do
            box = CrymbleUI::LayerBox.new(0.0, 0.0, nil, nil,
                alignment: CrymbleUI::Alignment::Center)

            child = TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 100.0))
            box.add_child(child)

            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)
            box.constrain_to_window_bounds(window_bounds)

            box.bounds.width.should eq(200.0)
            box.bounds.height.should eq(100.0)
            box.x.should eq(300.0)  # (800 - 200) / 2
            box.y.should eq(250.0)  # (600 - 100) / 2
        end

        it "falls back to window size when no children" do
            box = CrymbleUI::LayerBox.new(0.0, 0.0, nil, nil,
                alignment: CrymbleUI::Alignment::TopLeft, margin: 0.0)
            # No children added

            window_bounds = CrymbleUI::Rect.new(0.0, 0.0, 800.0, 600.0)
            box.constrain_to_window_bounds(window_bounds)

            # With no children, should fill window
            box.bounds.width.should eq(800.0)
            box.bounds.height.should eq(600.0)
            box.x.should eq(0.0)
            box.y.should eq(0.0)
        end
    end
end
