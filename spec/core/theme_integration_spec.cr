require "../spec_helper"
require "../../src/core/theme"

# Tests that verify widgets honor Theme.current for their default colors.
# These tests will FAIL until widget constructors are migrated (Step 4).
describe "Theme widget integration" do
  before_each do
    CrymbleUI::Theme.set(:light)
  end

  describe "Button" do
    it "uses theme button_text as default text_color" do
      btn = CrymbleUI::Button.new("Test")
      btn.text_color.should eq CrymbleUI::Theme.current.button_text
    end

    it "uses theme button_background as default background_color" do
      btn = CrymbleUI::Button.new("Test")
      btn.background_color.should eq CrymbleUI::Theme.current.button_background
    end

    it "uses theme button_border as default border_color" do
      btn = CrymbleUI::Button.new("Test")
      btn.border_color.should eq CrymbleUI::Theme.current.button_border
    end

    it "allows explicit color override" do
      custom = CrymbleUI::Color.new(255, 0, 0, 255)
      btn = CrymbleUI::Button.new("Test", text_color: custom)
      btn.text_color.should eq custom
    end
  end

  describe "Text" do
    it "uses theme text_default as default color" do
      t = CrymbleUI::Text.new("Hello")
      t.color.should eq CrymbleUI::Theme.current.text_default
    end
  end

  describe "TextInput" do
    it "uses theme input colors as defaults" do
      ti = CrymbleUI::TextInput.new
      ti.text_color.should eq CrymbleUI::Theme.current.input_text
      ti.background_color.should eq CrymbleUI::Theme.current.input_background
      ti.border_color.should eq CrymbleUI::Theme.current.input_border
      ti.focused_border_color.should eq CrymbleUI::Theme.current.input_border_focused
      ti.placeholder_color.should eq CrymbleUI::Theme.current.input_placeholder
    end
  end

  describe "theme switch affects new widgets" do
    it "creates button with dark theme colors after switch" do
      CrymbleUI::Theme.set(:dark)
      btn = CrymbleUI::Button.new("Dark")
      btn.background_color.should eq CrymbleUI::Theme.current.button_background
      # Dark button background should differ from light
      CrymbleUI::Theme.set(:light)
      btn.background_color.should_not eq CrymbleUI::Theme.current.button_background
    end

    it "creates text with dark theme color after switch" do
      CrymbleUI::Theme.set(:dark)
      t = CrymbleUI::Text.new("Dark")
      t.color.should eq CrymbleUI::Color.from_hex("#D4D4D4")
    end
  end
end
