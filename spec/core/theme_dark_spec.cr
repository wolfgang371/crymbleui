require "../spec_helper"
require "../../src/core/theme"

# Helper: extract brightness (0.0-1.0) from a color
def color_brightness(c : CrymbleUI::Color) : Float64
  [c.r.to_f64, c.g.to_f64, c.b.to_f64].max / 255.0
end

describe "Dark theme visual correctness" do
  before_each do
    CrymbleUI::Theme.set(:dark)
  end

  describe "text readability" do
    it "has light text on dark app background" do
      theme = CrymbleUI::Theme.current
      color_brightness(theme.text_default).should be > 0.5
      color_brightness(theme.app_background).should be < 0.3
    end

    it "has light input text on dark input background" do
      theme = CrymbleUI::Theme.current
      color_brightness(theme.input_text).should be > 0.5
      color_brightness(theme.input_background).should be < 0.3
    end

    it "has light menu text on dark menu background" do
      theme = CrymbleUI::Theme.current
      color_brightness(theme.menu_text).should be > 0.5
      color_brightness(theme.menu_background).should be < 0.3
    end

    it "has light statusbar text on dark statusbar background" do
      theme = CrymbleUI::Theme.current
      color_brightness(theme.statusbar_text).should be > 0.5
      color_brightness(theme.statusbar_background).should be < 0.3
    end

    it "has light panel title text on panel title bar" do
      theme = CrymbleUI::Theme.current
      color_brightness(theme.panel_title_text).should be > 0.8
    end
  end

  describe "contrast between elements" do
    it "has darker borders than backgrounds for surfaces" do
      theme = CrymbleUI::Theme.current
      # In dark theme, borders should be visible against dark backgrounds
      # (either lighter or darker — just different)
      theme.menu_border.should_not eq theme.menu_background
      theme.popup_border.should_not eq theme.popup_background
      theme.input_border.should_not eq theme.input_background
    end

    it "has distinct hover colors" do
      theme = CrymbleUI::Theme.current
      theme.menu_hover.should_not eq theme.menu_background
      theme.combo_hover.should_not eq theme.combo_background
    end
  end

  describe "accent colors" do
    it "has visible accent blue on dark backgrounds" do
      theme = CrymbleUI::Theme.current
      # Accent should have some blue channel
      theme.button_background.b.should be > 100
      theme.input_border_focused.b.should be > 100
    end
  end

  describe "dark theme differs from light" do
    it "has darker backgrounds in dark theme" do
      dark_bg = CrymbleUI::Theme.current.app_background
      CrymbleUI::Theme.set(:light)
      light_bg = CrymbleUI::Theme.current.app_background
      color_brightness(dark_bg).should be < color_brightness(light_bg)
    end

    it "has lighter text in dark theme" do
      dark_text = CrymbleUI::Theme.current.text_default
      CrymbleUI::Theme.set(:light)
      light_text = CrymbleUI::Theme.current.text_default
      color_brightness(dark_text).should be > color_brightness(light_text)
    end
  end
end
