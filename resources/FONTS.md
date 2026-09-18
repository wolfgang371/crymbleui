# Fonts shipped in `resources/`

## Cousine-Regular.ttf

Upstream: Cousine, by Steve Matteson for Google. Metric-compatible with Courier New, monospaced.

    Digitized data copyright (c) 2010-2012 Google Corporation.
    Cousine is a trademark of Google Inc. and may be registered in certain jurisdictions.
    Licensed under the Apache License, Version 2.0
    http://www.apache.org/licenses/LICENSE-2.0

### What is modified

**One glyph.** U+21BA ANTICLOCKWISE OPEN CIRCLE ARROW was added on 2026-09-16, taken from DejaVu
Sans Mono. Nothing else differs from upstream: no original glyph was altered, re-advanced or
removed, and the file is otherwise the shipped Google build (2333 glyphs, now 2334).

U+21BA is embrace's "revert to base" prefix. Cousine contains no curved or hooked arrow at all —
not U+21BA, U+21BB, U+21B6, U+21B7, U+27F2, U+27F3, U+21A9, nor U+238C — so there was nothing to
substitute, and embrace had been shipping U+2190 (←) in its place.

DejaVu Sans Mono shares this file's unitsPerEm of 2048, so the outline was copied without scaling.
Its advance was changed from DejaVu's 1233 to Cousine's 1229 and the outline shifted -2 units to
recentre it, per the equal-width rule below.

### The equal-width rule

Cousine is monospaced and the widget layer relies on it: every glyph in this file that occupies
space must have an advance width of **1229** units at unitsPerEm 2048 (non-spacing marks carry 0).
Anything merged in has to be GIVEN that advance and recentred within it — not inherit the donor's,
which will be close but not equal. A single odd advance is a column that will not line up.

**This is enforced, not merely written here.** `spec/rendering/font_invariants_spec.cr` reads the
file's own `hmtx`, `cmap`, `loca` and `glyf` tables and asserts both properties a merge can break:
that every glyph occupying space shares one advance, and that each merged codepoint maps to a glyph
with actual outlines — a cmap entry proves a mapping exists, not that any ink appears, and this bug
class is exactly "the character is fine everywhere except on screen". Point `CUI_FONT` at another
file to see the spec fail.

### Licensing, and why the notices are in the font file itself

The .ttf is embedded into the binary at compile time (`read_file`), so THIS FILE DOES NOT TRAVEL
with what we ship. Both licences want their notices to accompany the font software, and Apache 2.0
§4(b) wants a modified file to carry notice of the modification — so the notices live in the font's
own `name` table, which survives embedding:

| name ID | holds |
|---|---|
| 0 Copyright | Google's notice, the modification, and Bitstream's copyright + trademark notices |
| 5 Version | `Version 1.21; crymbleui 1` — the suffix is what marks it as modified |
| 10 Description | what was changed: one glyph, U+21BA, from DejaVu Sans Mono |
| 13 License | Apache 2.0, plus the Bitstream Vera permission notice in full |
| 3 Unique ID | `1.21;MONO;Cousine-Regular;crymbleui1` — two fonts must not share one unique ID; caches key on it |
| 1 Family / 7 Trademark | **unchanged** — see below |

The family name stays `Cousine`. Renaming (say to "Crymble Mono") would overclaim authorship for a
one-glyph change, and the alternative of dropping the glyph loses the feature; keeping the name and
declaring the modification in the metadata is the deliberate choice. The Google trademark notice is
a true statement and is kept for the same reason.

The added glyph's licence, which the name table carries in full:

    Copyright (c) 2003 by Bitstream, Inc. All Rights Reserved.
    Bitstream Vera is a trademark of Bitstream, Inc.
    DejaVu changes are in public domain.

    Permission is hereby granted, free of charge, to any person obtaining a copy of the fonts
    accompanying this license ("Fonts") and associated documentation files (the "Font Software"),
    to reproduce and distribute the Font Software, including without limitation the rights to use,
    copy, merge, publish, distribute, and/or sell copies of the Font Software, and to permit persons
    to whom the Font Software is furnished to do so, subject to the following conditions:

    The above copyright and trademark notices and this permission notice shall be included in all
    copies of one or more of the Font Software typefaces.

That licence also forbids using "Bitstream" or "Vera" in the name of a modified font; this file is
named Cousine, so that condition holds.

### What a consumer must show, and where that text lives

`CrymbleUI::SFMLRenderer::FONT_ATTRIBUTION` is the notice an About box shows. It lives beside
`EMBEDDED_FONT` because the obligation follows the file: that constant is a compile-time
`read_file`, so every consumer's binary contains this modified Cousine and owes the notice whether
or not it ever draws with it. A consumer composing its own wording is how the claim goes stale —
embrace's About said "version 1.21, Apache 2.0" of a font that by then also carried a DejaVu glyph.

It is deliberately NOT derived from `font_path`. An app may load its own font at runtime, and it
would be tempting to fall silent then — but the modified Cousine is still inside its binary, so the
notice would go silent exactly while it was still owed. An app that loads its own font must
additionally attribute THAT font; this library cannot do it for them, not knowing what was loaded.

`font_invariants_spec.cr` checks the constant against the font's own `name` table: if the file
contains U+21BA then the text must say "modified", must name DejaVu Sans Mono and the Bitstream Vera
licence, the font itself must carry the Bitstream notice, and the unique ID must no longer claim
upstream's. Point `CUI_FONT` at a stock Cousine and those requirements relax themselves.

### A correction, kept because it is the interesting part

The first version of this file claimed ◄ (U+25C4) and ► (U+25BA) had been merged in from Cantarell,
and that the font was "not stock" with 2275 codepoints "where the widely-circulated subset carries
249". **Both were wrong**, and a licensing document is a bad place to be wrong.

◄ and ► are ORIGINAL Cousine glyphs. The evidence is in the font: they are named `triaglf` and
`triagrt`, part of a contiguous foundry-named family (`triagup`/`triagrt`/`triagdn`/`triaglf`, glyph
indices 375-378) sitting mid-font — whereas a merged glyph arrives with an autogenerated name at the
END of the glyph order, which is exactly what `uni21BA` at index 2333 looks like. The 249 was
imgui's stripped subset, not upstream Cousine; against real upstream the difference here is one
glyph.

The claim came from reading `# from Cantarell-Regular.otf` above embrace's `FieldAffixes` as a
record of provenance. With the glyph names in hand it plainly is not: it says where the author FOUND
the characters, and the next line (`# e.g. via font-manager Cousine-Regular.ttf`) says how to check
Cousine already had them. A comment is not evidence of origin. The font is.
