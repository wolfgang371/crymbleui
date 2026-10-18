module CrymbleUI
  # The font crymble-ui embeds into every binary - both flavours draw with it (the native renderer loads it
  # into SFML, the web one into the page) unless an app loads its own.
  module EmbeddedFont
    # Embed font at compile time for self-contained binary.
    #
    # ⚠️  WINDOWS GLYPH GARBLING — see docs/WINDOWS_SFML_GL_SYNC_BUG.md
    # On Windows, SFML 3.0.0 + system GL drivers do not synchronize glyph
    # atlas uploads with subsequent reads, causing random characters to
    # render with the wrong glyph (stochastic across process launches).
    # The fix is an out-of-tree patch to SFML's Texture.cpp adding
    # glFinish() after every glTexImage2D / glTexSubImage2D. Without it,
    # text rendering on Windows is non-deterministic. The patched
    # sfml-graphics-s.lib MUST be used for Windows builds.
    BYTES = {{ read_file(__DIR__ + "/../../resources/Cousine-Regular.ttf") }}

    # WHAT AN APP SHIPPING THIS LIBRARY HAS TO SAY ABOUT THE FONT.
    #
    # The notice belongs here because the font does: BYTES is a compile-time read_file, so
    # every consumer's binary contains our modified Cousine and owes the notice whether or not it
    # ever draws with it. resources/FONTS.md has the full text and the reasoning; this is the line
    # an About box shows, so that a consumer is not left composing a licence notice about a file it
    # does not own — embrace hardcoded its own and it went stale the day the font was modified.
    #
    # NOT derived from a renderer's font_path, deliberately. A consumer may load its own font, and it would be
    # tempting to return nothing then — but the obligation attaches to DISTRIBUTION, not to what is
    # on screen: the modified Cousine is still inside their binary. An attribution that went silent
    # exactly when a custom font was loaded would go silent while the notice was still owed. An app
    # that loads its own font must additionally attribute THAT font, which this library cannot do
    # for it because it does not know what was loaded.
    ATTRIBUTION = [
      "Google Cousine-Regular font (version 1.21, modified, Apache 2.0 license)",
      "  incl. one glyph (U+21BA) from DejaVu Sans Mono, Bitstream Vera license",
    ]
  end
end
