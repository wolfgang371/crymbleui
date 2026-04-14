require "../spec_helper"
require "../../src/core/theme"

describe CrymbleUI::Theme do
  # Reset to light theme before each test for isolation
  before_each do
    CrymbleUI::Theme.set(:light)
  end

  describe "ThemeData" do
    it "parses light theme JSON without error" do
      theme = CrymbleUI::Theme.current
      theme.should be_a(CrymbleUI::ThemeData)
    end

    it "has correct light theme name" do
      CrymbleUI::Theme.current.name.should eq "Light"
    end

    it "has correct dark theme name" do
      CrymbleUI::Theme.set(:dark)
      CrymbleUI::Theme.current.name.should eq "Dark"
    end
  end

  describe ".current" do
    it "defaults to light theme" do
      CrymbleUI::Theme.current.name.should eq "Light"
    end

    it "returns ThemeData struct" do
      CrymbleUI::Theme.current.should be_a(CrymbleUI::ThemeData)
    end
  end

  describe ".set" do
    it "switches to dark theme" do
      CrymbleUI::Theme.set(:dark)
      CrymbleUI::Theme.current.name.should eq "Dark"
    end

    it "switches back to light theme" do
      CrymbleUI::Theme.set(:dark)
      CrymbleUI::Theme.set(:light)
      CrymbleUI::Theme.current.name.should eq "Light"
    end

    it "raises on unknown theme name" do
      expect_raises(Exception, "Unknown theme: nonexistent") do
        CrymbleUI::Theme.set(:nonexistent)
      end
    end
  end

  describe ".register" do
    it "registers a custom theme" do
      custom_json = CrymbleUI::Theme::LIGHT_JSON.gsub("\"Light\"", "\"Custom\"")
      custom = CrymbleUI::ThemeData.from_json_string(custom_json)
      CrymbleUI::Theme.register(:custom, custom)
      CrymbleUI::Theme.set(:custom)
      CrymbleUI::Theme.current.name.should eq "Custom"
    end
  end

  describe ".available" do
    it "includes light and dark" do
      names = CrymbleUI::Theme.available
      names.should contain(:light)
      names.should contain(:dark)
    end
  end

  describe "light theme color tokens" do
    it "has correct app background" do
      CrymbleUI::Theme.current.app_background.should eq CrymbleUI::Color.new(245, 245, 245, 255)
    end

    it "has correct button colors" do
      theme = CrymbleUI::Theme.current
      theme.button_text.should eq CrymbleUI::Color.new(255, 255, 255, 255)
      theme.button_background.should eq CrymbleUI::Color.new(0, 120, 215, 255)
      theme.button_border.should eq CrymbleUI::Color.new(0, 100, 180, 255)
    end

    it "has correct text default color" do
      CrymbleUI::Theme.current.text_default.should eq CrymbleUI::Color.new(0, 0, 0, 255)
    end

    it "has correct input colors" do
      theme = CrymbleUI::Theme.current
      theme.input_text.should eq CrymbleUI::Color.new(0, 0, 0, 255)
      theme.input_background.should eq CrymbleUI::Color.new(255, 255, 255, 255)
      theme.input_border.should eq CrymbleUI::Color.new(180, 180, 180, 255)
      theme.input_border_focused.should eq CrymbleUI::Color.new(0, 120, 215, 255)
      theme.input_placeholder.should eq CrymbleUI::Color.new(150, 150, 150, 255)
      theme.input_selection.should eq CrymbleUI::Color.new(173, 214, 255, 255)
    end

    it "has correct checkbox colors" do
      theme = CrymbleUI::Theme.current
      theme.checkbox_text.should eq CrymbleUI::Color.new(0, 0, 0, 255)
      theme.checkbox_box.should eq CrymbleUI::Color.new(100, 100, 100, 255)
      theme.checkbox_check.should eq CrymbleUI::Color.new(0, 120, 215, 255)
    end

    it "has correct menu colors" do
      theme = CrymbleUI::Theme.current
      theme.menu_text.should eq CrymbleUI::Color.new(0, 0, 0, 255)
      theme.menu_background.should eq CrymbleUI::Color.new(250, 250, 250, 255)
      theme.menu_hover.should eq CrymbleUI::Color.new(230, 230, 230, 255)
      theme.menu_border.should eq CrymbleUI::Color.new(200, 200, 200, 255)
    end

    it "has correct menu item colors" do
      theme = CrymbleUI::Theme.current
      theme.menu_item_text.should eq CrymbleUI::Color.new(0, 0, 0, 255)
      theme.menu_item_shortcut.should eq CrymbleUI::Color.new(100, 100, 100, 255)
      theme.menu_item_hover.should eq CrymbleUI::Color.new(0, 120, 215, 255)
    end

    it "has correct menubar colors" do
      theme = CrymbleUI::Theme.current
      theme.menubar_background.should eq CrymbleUI::Color.new(250, 250, 250, 255)
      theme.menubar_border.should eq CrymbleUI::Color.new(200, 200, 200, 255)
    end

    it "has correct window panel colors" do
      theme = CrymbleUI::Theme.current
      theme.panel_title_bar.should eq CrymbleUI::Color.new(0, 100, 180, 255)
      theme.panel_title_bar_active.should eq CrymbleUI::Color.new(0, 120, 215, 255)
      theme.panel_title_bar_inactive.should eq CrymbleUI::Color.new(0, 80, 150, 255)
      theme.panel_title_text.should eq CrymbleUI::Color.new(255, 255, 255, 255)
      theme.panel_border.should eq CrymbleUI::Color.new(0, 80, 160, 255)
      theme.panel_background.should eq CrymbleUI::Color.new(240, 240, 240, 255)
    end

    it "has correct popup colors" do
      theme = CrymbleUI::Theme.current
      theme.popup_background.should eq CrymbleUI::Color.new(255, 255, 255, 255)
      theme.popup_border.should eq CrymbleUI::Color.new(180, 180, 180, 255)
    end

    it "has correct statusbar colors" do
      theme = CrymbleUI::Theme.current
      theme.statusbar_text.should eq CrymbleUI::Color.new(50, 50, 50, 255)
      theme.statusbar_background.should eq CrymbleUI::Color.new(240, 240, 240, 255)
      theme.statusbar_border.should eq CrymbleUI::Color.new(180, 180, 180, 255)
    end

    it "has correct scrollbar colors" do
      theme = CrymbleUI::Theme.current
      theme.scrollbar_track.should eq CrymbleUI::Color.new(220, 220, 220, 255)
      theme.scrollbar_thumb.should eq CrymbleUI::Color.new(150, 150, 150, 255)
      theme.scrollbar_arrow.should eq CrymbleUI::Color.new(100, 100, 100, 255)
    end

    it "has correct combo box colors" do
      theme = CrymbleUI::Theme.current
      theme.combo_text.should eq CrymbleUI::Color.new(0, 0, 0, 255)
      theme.combo_background.should eq CrymbleUI::Color.new(255, 255, 255, 255)
      theme.combo_border.should eq CrymbleUI::Color.new(180, 180, 180, 255)
      theme.combo_hover.should eq CrymbleUI::Color.new(230, 230, 230, 255)
      theme.combo_selected.should eq CrymbleUI::Color.new(120, 160, 220, 255)
    end

    it "has correct separator color" do
      CrymbleUI::Theme.current.separator_color.should eq CrymbleUI::Color.new(200, 200, 200, 255)
    end

    it "has correct grid colors" do
      theme = CrymbleUI::Theme.current
      theme.grid_content_background.should eq CrymbleUI::Color.new(240, 240, 240, 255)
    end

    it "has correct ruler colors" do
      theme = CrymbleUI::Theme.current
      theme.ruler_background.should eq CrymbleUI::Color.new(220, 220, 225, 255)
      theme.ruler_label.should eq CrymbleUI::Color.new(80, 80, 85, 255)
      theme.ruler_line.should eq CrymbleUI::Color.new(180, 180, 185, 255)
    end

    it "has correct drag colors" do
      theme = CrymbleUI::Theme.current
      theme.drag_highlight.should eq CrymbleUI::Color.new(180, 220, 255, 255)
      theme.dropzone_hover.should eq CrymbleUI::Color.new(180, 220, 255, 255)
      theme.dropzone_background.should eq CrymbleUI::Color.new(240, 240, 240, 255)
    end
  end

  describe "light theme brightness constants" do
    it "has correct hover brightness" do
      CrymbleUI::Theme.current.brightness_hover.should eq 0.15
    end

    it "has correct focus brightness" do
      CrymbleUI::Theme.current.brightness_focus.should eq 0.35
    end

    it "has correct drag opacity" do
      CrymbleUI::Theme.current.brightness_drag_opacity.should eq 0.4
    end

    it "has correct cursor delta" do
      CrymbleUI::Theme.current.brightness_cursor_delta.should eq -40
    end
  end

  describe "dark theme" do
    before_each do
      CrymbleUI::Theme.set(:dark)
    end

    it "has different background from light" do
      dark_bg = CrymbleUI::Theme.current.app_background
      CrymbleUI::Theme.set(:light)
      light_bg = CrymbleUI::Theme.current.app_background
      dark_bg.should_not eq light_bg
    end

    it "has different text color from light" do
      dark_text = CrymbleUI::Theme.current.text_default
      CrymbleUI::Theme.set(:light)
      light_text = CrymbleUI::Theme.current.text_default
      dark_text.should_not eq light_text
    end

    it "has all required color tokens" do
      theme = CrymbleUI::Theme.current
      # Spot-check that all tokens are non-nil (struct fields are always set)
      theme.app_background.should be_a(CrymbleUI::Color)
      theme.button_text.should be_a(CrymbleUI::Color)
      theme.button_background.should be_a(CrymbleUI::Color)
      theme.input_text.should be_a(CrymbleUI::Color)
      theme.panel_title_bar.should be_a(CrymbleUI::Color)
      theme.scrollbar_track.should be_a(CrymbleUI::Color)
      theme.grid_content_background.should be_a(CrymbleUI::Color)
      theme.ruler_background.should be_a(CrymbleUI::Color)
    end
  end

  describe "theme isolation between switches" do
    it "does not leak state between theme switches" do
      light_button = CrymbleUI::Theme.current.button_background
      CrymbleUI::Theme.set(:dark)
      dark_button = CrymbleUI::Theme.current.button_background
      CrymbleUI::Theme.set(:light)
      CrymbleUI::Theme.current.button_background.should eq light_button
      dark_button.should_not eq light_button
    end
  end
end
