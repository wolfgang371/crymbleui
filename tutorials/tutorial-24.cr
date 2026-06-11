# Tutorial 24: Image Widget
# =========================
# Displaying images with tinting and sizing options.
#
# Key concepts:
# - embed_image("path") bakes a PNG/JPG into the binary at compile time, so the
#   standalone build needs no external files; image(source, width:, height:) shows it.
#   (Pass a plain String path to image(...) instead to load from disk at runtime.)
# - tint: applies a color tint (multiply blend)
# - Images auto-size to parent constraints if no explicit size given
#
# Run with: shards build tutorial-24 && ./bin/tutorial-24

require "../src/crymble-ui"

include CrymbleUI

class Tutorial24App < CrymbleUI::App
  LOGO = embed_image("tutorials/crystal_logo.png")

  def build : CrymbleUI::Widget
    window("Tutorial 24: Image Widget", 600, 400) do
      vstack(padding: 15.0, spacing: 15.0) do
        text("Image Widget Examples", font_scale: 1)

        hstack(spacing: 20.0) do
          vstack(spacing: 5.0) do
            text("Original (128×128)", font_scale: -1)
            image(LOGO, width: 128.0, height: 128.0)
          end

          vstack(spacing: 5.0) do
            text("Red tint", font_scale: -1)
            image(LOGO, width: 128.0, height: 128.0,
                  tint: Color.new(255, 100, 100, 255))
          end

          vstack(spacing: 5.0) do
            text("Blue tint", font_scale: -1)
            image(LOGO, width: 128.0, height: 128.0,
                  tint: Color.new(100, 100, 255, 255))
          end

          vstack(spacing: 5.0) do
            text("Semi-transparent", font_scale: -1)
            image(LOGO, width: 128.0, height: 128.0,
                  tint: Color.new(255, 255, 255, 128))
          end
        end

        separator

        text("Small (48×48):", font_scale: -1)
        hstack(spacing: 10.0) do
          image(LOGO, width: 48.0, height: 48.0)
          image(LOGO, width: 48.0, height: 48.0, tint: Color.new(100, 255, 100, 255))
          image(LOGO, width: 48.0, height: 48.0, tint: Color.new(255, 200, 50, 255))
        end
      end
    end
  end
end

CrymbleUI.run(Tutorial24App.new)
