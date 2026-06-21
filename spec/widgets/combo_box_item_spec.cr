require "../spec_helper"
require "../../src/widgets/combo_box_item"

describe CrymbleUI::ComboBoxItem do
  describe "#initialize" do
    it "creates item with label" do
      item = CrymbleUI::ComboBoxItem.new("Apple")
      item.label_text.should eq("Apple")
    end

    it "accepts id parameter" do
      item = CrymbleUI::ComboBoxItem.new("Banana", id: "banana_item")
      item.id.should eq("banana_item")
    end

    it "accepts value parameter for data binding" do
      item = CrymbleUI::ComboBoxItem.new("Cherry", value: "cherry_val")
      item.value.should eq("cherry_val")
    end

    it "defaults value to label if not provided" do
      item = CrymbleUI::ComboBoxItem.new("Date")
      item.value.should eq("Date")
    end
  end

  describe "#label" do
    it "returns 'listboxitem' for path_id generation" do
      item = CrymbleUI::ComboBoxItem.new("Test")
      item.label.should eq("listboxitem")
    end
  end

  describe "#measure" do
    it "returns height based on font size" do
      item = CrymbleUI::ComboBoxItem.new("Test")
      constraints = CrymbleUI::BoxConstraints.new
      size = item.measure(constraints)

      # Height should be font size + padding
      size.height.should be > 20.0
    end

    it "returns width based on label text" do
      item = CrymbleUI::ComboBoxItem.new("Short")
      item2 = CrymbleUI::ComboBoxItem.new("A much longer label text")
      constraints = CrymbleUI::BoxConstraints.new

      size1 = item.measure(constraints)
      size2 = item2.measure(constraints)

      size2.width.should be > size1.width
    end
  end

  describe "selection state" do
    it "starts unselected" do
      item = CrymbleUI::ComboBoxItem.new("Test")
      item.selected?.should be_false
    end

    it "can be selected" do
      item = CrymbleUI::ComboBoxItem.new("Test")
      item.selected = true
      item.selected?.should be_true
    end

  end

  describe "#on_mouse_enter and #on_mouse_exit" do
    it "sets hovered state" do
      item = CrymbleUI::ComboBoxItem.new("Test")
      item.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      item.on_mouse_enter
      item.needs_render?.should be_true
    end

    it "clears hovered state on exit" do
      item = CrymbleUI::ComboBoxItem.new("Test")
      item.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

      item.on_mouse_enter
      item.get_primitives(item.bounds) # real render: captures `hovered` (reactive, no manual mark)

      item.on_mouse_exit
      item.needs_render?.should be_true
    end
  end

  describe "#on_click" do
    it "calls callback with value" do
      clicked_value = nil
      item = CrymbleUI::ComboBoxItem.new("Apple", value: "apple_val") do |val|
        clicked_value = val
      end

      item.on_click
      clicked_value.should eq("apple_val")
    end
  end

  describe "#to_primitives" do
    it "generates label text primitive" do
      item = CrymbleUI::ComboBoxItem.new("Test Label")
      bounds = CrymbleUI::Rect.new(0, 0, 150, 30)

      primitives = item.to_primitives(bounds)

      # Should have at least a text primitive
      text_prims = primitives.select { |p| p.is_a?(CrymbleUI::DrawText) }
      text_prims.size.should be >= 1
    end

    it "generates hover background when hovered" do
      item = CrymbleUI::ComboBoxItem.new("Test")
      item.on_mouse_enter
      bounds = CrymbleUI::Rect.new(0, 0, 150, 30)

      primitives = item.to_primitives(bounds)

      # Should have fill_rect for hover background
      fill_prims = primitives.select { |p| p.is_a?(CrymbleUI::FillRect) }
      fill_prims.size.should be >= 1
    end

    it "generates selected background when selected" do
      item = CrymbleUI::ComboBoxItem.new("Test")
      item.selected = true
      bounds = CrymbleUI::Rect.new(0, 0, 150, 30)

      primitives = item.to_primitives(bounds)

      # Should have fill_rect for selected background
      fill_prims = primitives.select { |p| p.is_a?(CrymbleUI::FillRect) }
      fill_prims.size.should be >= 1
    end
  end
end
