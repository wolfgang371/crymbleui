require "../spec_helper"
require "../../src/rendering/sfml_renderer"

# What an app's About shows for the backend it was built with - asked, not named by the app, so one About is
# right in every flavour. Natively: the SFML libraries linked, then the embedded font's attribution (the lines
# an About printed itself before this existed).
describe "CrymbleUI.backend_notices (native)" do
  it "names CSFML and SFML with their versions, then the embedded font's attribution" do
    CrymbleUI.backend_notices.should eq [
      "CSFML (version #{SF::VERSION}, Zlib license)",
      "SFML (version #{SF::SFML_VERSION}, Zlib license)",
    ] + CrymbleUI::EmbeddedFont::ATTRIBUTION
  end

  it "keeps the font attribution reachable under its old name" do
    CrymbleUI::SFMLRenderer::FONT_ATTRIBUTION.should eq CrymbleUI::EmbeddedFont::ATTRIBUTION
  end
end
