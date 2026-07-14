require "../spec_helper"
require "../../src/core/theme"

# Theme.register_colors lets an APP own its color tokens (naming + values) instead
# of them living in the lib's generic theme JSON. A token merges into the named
# variant and resolves via Theme.current["token"] after the matching Theme.set,
# surviving light<->dark toggles. Unknown tokens still raise (no silent fallback).
describe "CrymbleUI::Theme.register_colors" do
  it "resolves an app-registered token for its variant" do
    color = CrymbleUI::Color.from_hex("#123456")
    CrymbleUI::Theme.register_colors(:dark, {"spec.reg_token" => color})
    CrymbleUI::Theme.set(:dark)
    CrymbleUI::Theme.current["spec.reg_token"].should eq(color)
  end

  it "survives a light<->dark round-trip (per-variant values)" do
    dark = CrymbleUI::Color.from_hex("#abcdef")
    light = CrymbleUI::Color.from_hex("#fedcba")
    CrymbleUI::Theme.register_colors(:dark, {"spec.rt_token" => dark})
    CrymbleUI::Theme.register_colors(:light, {"spec.rt_token" => light})
    CrymbleUI::Theme.set(:dark)
    CrymbleUI::Theme.set(:light)
    CrymbleUI::Theme.set(:dark)
    CrymbleUI::Theme.current["spec.rt_token"].should eq(dark)
    CrymbleUI::Theme.set(:light)
    CrymbleUI::Theme.current["spec.rt_token"].should eq(light)
  end

  it "still raises for an unregistered token (no silent fallback)" do
    CrymbleUI::Theme.set(:dark)
    expect_raises(KeyError) { CrymbleUI::Theme.current["spec.never_registered"] }
  end

  it "raises when registering for an unknown variant" do
    expect_raises(Exception, /Unknown theme/) do
      CrymbleUI::Theme.register_colors(:no_such_variant, {"spec.x" => CrymbleUI::Color.from_hex("#000000")})
    end
  end
end
