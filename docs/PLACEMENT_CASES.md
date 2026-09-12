# Where content sits in a band — the cases

The rule itself is in `ARCHITECTURE.md` ("Where content sits in a band"). This file is the list of
things it must get right, and **why each one is in the list**. It exists because the rule was
rewritten three times on 2026-09-08 alone: each rewrite satisfied the case in front of it and broke
one that nobody could name, because the reasons lived in commit messages instead of here.

Rules for this file:

- A case is a SITUATION and an OUTCOME, never a mechanism. "A compound header's label stays visible
  while its group is partly on screen", not "clamp to visible_lo".
- Every case names where it came from. A case with no origin is a guess and should be deleted.
- Every case names what GUARDS it. `UNGUARDED` is the useful entry: it says the next rewrite can
  break this and the suite will stay green — which is exactly what happened to UC-2.
- When a change conflicts with a case, the case is the thing to argue with. Change it deliberately,
  in this file, with a reason — do not let it rot into a comment nobody reads.

## The cases

| # | Situation | Must happen | Why / origin | Guard |
|---|---|---|---|---|
| UC-1 | A compound header spans many rows; its group is partly scrolled off | Its label stays visible, inside the visible part of the SPAN it names | The label names the whole group, so placing it against its box puts it in the wrong place entirely. The defect the rule was written for | `compound_label_visibility` |
| UC-2 | A ruler number, a row header and a value all name the SAME line | They sit on one line, not three | Field report #45 — "'1', 'a' and '1' all at different vpos!!" | I9 |
| UC-3 | A value taller than the band | It is NOT moved; it scrolls and is clipped by its box | You must be able to read past a long value's first screenful — core `doc/08-shapes.md` | sweep S scope, I6 |
| UC-4 | A block that overflows its box | Line 1 is never the cut one (top-aligned) | You read the first line first | `vcentered_block_y` regimes |
| UC-5 | An ordinary row, roughly as tall as its text, cut by the viewport edge | Its labels are never pulled UP; they clip like the cell background | Field reports #74/#75. Holding bought a few pixels of visibility and cost visible jitter on every resize | I10, sweep T |
| UC-6 | A row made TALL by a multiline cell; a SHORT cell in that row | The short cell's label is CENTRED in that row | Wolfgang 2026-09-10: "vcentering on higher cells where applicable (e.g. single-text-line in higher or combined cells)". Between 2026-09-08 and 2026-09-10 this said "sits on the row's FIRST line" (from #78) and was wrong | I13 |
| UC-7 | Same tall row, scrolled up under the sticky header | The short cell's label must not disappear under the header | Why plain top-alignment cannot be the answer on its own (Wolfgang, 2026-09-08) | I14, sweep S |
| UC-8 | Two adjacent labels approach each other | They never converge or stack | Field report #40 | I4 |
| UC-9 | Any input moves by n px | Nothing moves further than n | Every jump report this arc | sweep J |
| UC-10 | Any cell | Content is never displaced outside its own box | Field reports #55, #58–#60 | sweep X |
| UC-11 | The band crosses the content's own extent | No step as it crosses | Reported as 6px of ink for 1px of panel height | I6 |
| UC-12 | The panel is resized a pixel at a time | Content does not step inside its box | Field reports of text jumping a line on resize | I5 |
| UC-13 | A cell whose ink did not move | Is not repainted | Perf: 22.4ms/frame, two-thirds of it invisible cells. Was "a cell that can show nothing is not repainted" until 2026-09-12: true of the SCREEN, false of the CACHE, because the viewport cache blit-shifts a cell's pixels back into view without re-rendering it (UC-27) | I7 + `placement_cost_spec` |
| UC-27 | A cell leaves the band and its ink moves in the same frame | It is repainted anyway | The 2026-09-10 rendering glitch. `handle_viewport_cache_scroll` blit-shifts the content layer's buffer, so pixels of cells outside the band come back into view unrendered; a cell that took its ink with it on the way out shows the old position. Only expressible at WHEEL-SIZED steps -- swept 3px at a time the ink reaches its clamp before the cell leaves, and 1100+ moves produced 0 of this class (step 50: 253) | I7 + `cache_validation_spec` (-Dcache_validation) |
| UC-14 | A held label whose visible slice has room for it | Is not clipped | The `slack` CAP dragged labels out of the band; 8.5px of 14 shown with 27px of room | sweep S |

| UC-15 | A ruler number and a cell on the same line, that line cut by the viewport | They stay on one line | They are different glyph sizes, so a hold that clamps each by its OWN height pushes them by different amounts — measured at up to 4.2px apart on a cut row | I9 |
| UC-16 | A compound label, panel collapsed until its span barely shows | It stays visible | #80/#81 — `a` dropped out through the bottom border. Its natural place is the middle of a span far taller than the viewport | sweep S, I15 |
| UC-26 | A group leaving at the leading edge | Its label never STALLS, and lands on the group's last visible row | Images #93-#96, both halves at once: "stays sticky ... before scrolling out entirely" and "'a' and '4' don't scroll out level at the end". They read as contradictory for two days because the first was operationalised as "offset inside the span is constant", which is a different property and forbids the second | `compound_scroll_out_spec` |
| UC-25 | Two groups on screen, one clipped at the TOP and one at the BOTTOM | Their labels move at the SAME rate — half the scroll | Images #105/#106, 2026-09-11: "r1a having ruler speed and r1b half of it — this is a bug". Holding the leading edge by the span's overflow made `lo` track the span's bottom: full speed, then jammed against the edge | `compound_edge_symmetry_spec` |
| UC-24 | A group hanging off the FAR edge, the panel then grown | Its label keeps moving for as long as more of the group comes into view, at half the panel's rate | Images #103/#104, 2026-09-11: "'b' only moves the first half of the full spanned height - why?" A position cap at the far edge rides the edge 1:1 and releases at the span's centre — half the span, exactly | `compound_scroll_out_spec` |
| UC-23 | A group TALLER than the viewport, scrolled into its middle | Its label sits in the middle of the part you can SEE, not against an edge | Images #99/#100, 2026-09-10: "it's placed at the very top, long before being scrolled out — this doesn't look nice" | `compound_scroll_out_spec` |
| UC-22 | A row TALLER than the viewport | Its content stays on screen, and the line's cells stay level | Images #97/#98, 2026-09-10: "the ruler isn't staying in the viewport"; "it's always visible on the upper part, but not in the lower one". The rule had a floor at the leading edge and no ceiling | `tall_row_visibility_spec` |
| UC-21 | A SMALL group scrolling out through the top | Its label leaves WITH the group, never lingering at the edge | Images #93-#96, 2026-09-10: "see how 'a' stays sticky again before scrolling out entirely?" A leading-edge clamp made the label drift 25.5px down through its own span | `compound_scroll_out_spec` |
| UC-17 | The band passes through one line's height | No step | The not-moved exit for long values was swallowing single-line labels too: 198.5px for 1px of resize | sweep J/V |
| UC-20 | A compound cell | Its label is centred in the part of the SPAN it names that you can see | Wolfgang 2026-09-10: "of course vcentering was always for compound cells". Held the opposite (level with its span's first row) for two days, from #83/#84 — which were the HOLD pushing a pinned compound and its row-mate by different amounts, fixed in `held_in_region` | I15 |
| UC-19 | A label frozen under the sticky header | Sits below the edge by half of what is left of its line; never flush on it | #82 — "the freezing is a couple of bits too high". Flush is 5.5px above where that same label sits in any row, and reads as shaved against the header. Delivered by the band clamp itself now: the slice shrinks continuously, so the label approaches the edge and leaves with its line rather than jamming | I14 |

## The rule, and when centring outranks levelness

**There is ONE rule: content is centred in the part of its region you can SEE, then confined to its
own box.** A region is the cell's own row for an ordinary cell and for a ruler number; the whole
SPAN for a compound. There are no conditions in it — not on the region's size, not on which edge
clips it, not on whether it is a row or a span.

It had all three of those conditions between 2026-09-08 and 2026-09-11, and every one of them was
there to protect the same misreading: that "sticky" (#93-#96) meant the label's offset inside its
span must not change. It means the label must not STOP. A region clamp never stops anything; a
position clamp does, and the rule had one.

**Levelness is not a second rule. It is what centring PRODUCES when two cells share a region.** That
is the thing this arc kept getting wrong: it was treated as an independent requirement, and every
attempt to enforce it directly (align on the row's first line, push a compound onto its span's first
row) broke the centring that produces it everywhere else. Asking "should these two be level?" is
answered by asking "do they name the same region?":

| Two cells | Same region? | Level? |
|---|---|---|
| A ruler number, a row header and a value on one line | yes — that row | **Always**, at rest and while held (UC-2, #45) |
| A compound and the cells of a row its span covers | **no** — a span is not a row | No. They never named the same thing, so there is nothing to reconcile (UC-20) |
| A one-line label and a multiline block in the same row | yes, but different content extents | No — each is placed as what it is (UC-6, UC-4) |
| Any two cells whose regions have climbed above the band | — | **Yes**: both sit at `band_lo` plus their own padding, capped at a line (UC-19, #87) |

So centring never *overrules* levelness in a contest. Where two cells share a region and an extent,
centring hands you levelness for free; where they do not, levelness was never a claim about them.
The one place the two genuinely meet is the last row of that table -- at the band edge the push,
not the region, decides -- and it is written to keep centres together: the floor `band_lo + pad`
with `pad` capped at one line puts a cell's CENTRE at `band_lo + region_size/2` whatever its glyph
size, which is why a ruler number and its cell stay on one line while both are frozen (UC-15).

**The one asymmetry, and why it has to be there.** A multi-line block anchors at its region's top
instead of centring. A span can be many screens tall, and a centred label then sits half a span down,
off the bottom of the screen, with its group plainly on view (#80/#81, UC-16). The pull-up that would
let it centre cannot be written: it must be measured in terms both cells share, or a ruler number and
its cell ride the bottom edge by different amounts -- measured at 4.2px when this was tried on
2026-09-10 -- and no shared form exists for a region taller than the band.

## How UC-5 and UC-6 were resolved

- **UC-6 is centring**, not a rescue. A one-line label in a tall row sits in the middle of that row,
  which is where it sat for years and where Wolfgang asked for it back on 2026-09-10. The version
  that pinned it to the row's first line lived for two days and produced "seems level, now, finally,
  but I see no vcentering at all".
- **UC-5 costs nothing.** Content is bounded by a slice of its OWN region, so it can never travel
  further than that region does and never rises above the region's top — the unbounded chase that
  caused the jitter of #74/#75 is not expressible in this rule.

## What each instrument can and cannot see

| instrument | what it sweeps | what it can catch | what it CANNOT |
|---|---|---|---|
| `spec/widgets/virtual_matrix/placement_invariants_spec` (I4–I15, nine of them; I1/I2/I3/I8/I11/I12 were folded into the sweep and `compound_label_visibility` when the overspecified cases were trimmed) | Named cases, each written after a field report, swept a pixel at a time | The exact defects reported, and their return | Anything nobody thought to write down. UC-2 went unguarded from the day it was fixed until 2026-09-08 |
| `spec/widgets/virtual_matrix/placement_sweep_spec` | 5 fixtures x 4 inputs, a pixel at a time, 7 properties on every label in every frame | Whatever is there, including in regimes nobody considered — it found a 198.5px jump at one panel height in one fixture | Anything outside its fixtures' shapes, and anything about actual PIXELS: it reads placement, not paint |
| `spec/widgets/virtual_matrix/compound_scroll_out_spec` | A shape of SMALL groups scrolled until each leaves, and a viewport small enough that a group covers the band | A group's label drifting inside its own span (the "sticky" of #93-#96), and a long group's label parking against an edge (#99/#100) | Anything about a group that fits AND never moves — its two examples both need travel |
| `spec/widgets/virtual_matrix/tall_row_visibility_spec` | A row taller than the viewport, swept a pixel at a time | Content placed off-band while its own line is on screen (#97/#98), and that line's cells parting | The ruler WIDGET's own band: in this harness a matrix's content layer is sized to the viewport, so the two agree and the mismatch cannot arise (I9 catches that instead) |
| `core/spec/gui/perspective_placement_invariants_spec` | The same properties on embrace's REAL pivot | Defects that need the real adapter — it found the box-clipping one crymbleui's fixtures never produced | Text metrics: `measure_text` returns 0x0 in core specs, so auto-size never expands a row there |

The seven sweep properties: **J** nothing moves further than the input that moved it · **V** no abrupt
change of speed · **R** no reversal while the input goes one way · **T** never above the rule's own answer, or its box's bottom edge, whichever is higher ·
**B** never past the region's trailing end · **S** visible whenever the rule could have placed it so ·
**X** never outside its own box.

**A guard on a fixture that cannot produce the situation is not a guard.** I14 — the guard for #82
and, after B4 was deleted, for #87 — ran for two days on a fixture whose content was SHORTER than
its viewport. Nothing ever scrolled, so it asserted on 0 of the 202 cells it inspected, and
reinstating the defect left it green. It now runs on a shape that pushes, and it asserts on its own
coverage (`push-BINDING > 20`, `compound > 5`) so that going dead again is itself a failure. Ask of
every example in this file: how many samples reached the assertion, and does the defect turn it red?

**The instruments have been wrong more often than the code.** I9 accused the code twice (matching
column-header cells against row-ruler labels; then a bound finer than the pixel grid the two are
drawn on), I13 once (demanding a block and a label stay level through a scroll where they correctly
part), and the sweep's own first run reported 34890 violations that were one harness bug. Read a
failure as a question about which of the two is wrong, not as a verdict on the code.

## The regime matrix — what is covered, and what is NOT

Every defect found on 2026-09-10..11 lived in a regime no fixture contained: a row taller than the
viewport (#97/#98), a group taller than the viewport (#99), a group hanging off the far edge
(#103/#104). The cases above were each written AFTER a report, so the suite's shape is the shape of
what Wolfgang happened to exercise. This table exists so the next gap can be found by reading rather
than by him finding it.

The axes that actually change the answer, from the rule itself: what the content is (one line or a
block), what its region is (its row, or a span), whether that region fits in the band, which edge it
crosses, whether its box still equals its region (a pinned clone's does not), and what moves it.

| content | region | vs band | crossing | fixture |
|---|---|---|---|---|
| one line | its row | fits | inside | every fixture, at rest |
| one line | its row | fits | leading | `placement_invariants` I14 (`pushed_matrix`), sweep |
| one line | its row | fits | far | sweep (`height`), `placement_boxes` B1 |
| one line | its row | **exceeds** | either | `tall_row_visibility` (12-line sibling in a 160px band) |
| block | its row | fits | inside | `reported_shape`, sweep "tall row" |
| block | its row | fits | leading/far | sweep; UC-3's exit covers "cannot be shown whole" |
| block | its row | **exceeds** | either | sweep "very tall row", `tall_row_visibility` |
| one line | a SPAN | fits | inside | `reported_shape`, `compound_scroll_out` |
| one line | a SPAN | fits | leading | `compound_scroll_out` (rides out, 0.0px drift) |
| one line | a SPAN | fits | far | `compound_scroll_out` grow test; `compound_enters_at_content_speed` |
| one line | a SPAN | **exceeds** | leading | `compound_scroll_out` tall-group; `compound_label_visibility` |
| one line | a SPAN | **exceeds** | far | `compound_label_visibility` (#45/#50, clusters thousands of px tall) |
| any | box != region (PINNED clone) | — | leading | `placement_boxes` B1, and only there |

**The four gaps this table named on 2026-09-11 were closed the same day.** All four turned out to
hold no user-visible defect; what they were missing was a guard, and in two cases the attempt to
write one taught something the code did not know it was saying.

- **A ROW's height changing under a span** → `span_resize_spec`. Three examples: the label moves at
  most HALF of what the span's extent changed by (measured: exactly 0.5, never a step), it stays
  centred in its span across 69 size-by-scroll cases, and a re-fit is driven the way typing drives
  it (`auto_size` off, on, flush). Verified RED at 60.0px.
  It also found a DEAD CONDITION — `... if size > band` on the leading-edge clause, which never did
  anything because the expression it guarded already degraded to `pos` on its own. That clause and
  its two successors are all gone now: the rule has no conditions at all (see the section above).
- **A MULTI-LINE label in a COMPOUND region** → `span_resize_spec`, third example. The block branch
  had genuinely never run against a span; it anchors at the span's top and stays inside it, which is
  what the example asserts (containment, not a centre — a block is not centred).
- **A pinned clone at the FAR edge** → `pinned_clone_spec`. Measured first: over 400px of scroll the
  demo yields 398 pinned samples, 200 of them with the span past the far edge, so the case is real
  rather than imagined. The label stays inside its own box at both ends; verified RED by disabling
  `confine` (9 labels outside their box). A second example was written and NOT shipped — it stayed
  green with the far clamp, the box bounds AND the pinned floor each removed in turn, because its
  own filter made it a tautology.
- **The X axis** → `column_ruler_x_spec`, and the gap is far narrower than this table first claimed:
  `InkRegion` is a Y-only record, so CELLS do no horizontal region placement at all. Exactly one
  caller places on X — the column ruler — and it now has the X twin of #97/#98: a column wider than
  the viewport keeps its label on screen, and no label moves more than the scroll that moved it.
  Verified RED at 220 off-band placements. Scoped like its Y twin: a column LEAVING takes its label
  with it, and a column ARRIVING with less visible than the glyph is wide shows it progressively —
  forcing either fully into view is the 1:1 edge-riding of #74/#75.

**The `pinned` heuristic is gone** (2026-09-11): the matrix tells the rule, instead of the rule
guessing from coordinates. A compound on a sticky column outside the sticky rows has its Y box set
by `StickyMath.compound_axis`, which is what pinning IS. The guess disagreed with the fact on 5861
samples across these suites — always calling a pinned box unpinned when its span happened to fit —
and produced identical placement in every one, because the floor is inert exactly where it
misjudged. `InkRegion` lost its `box` field with it.

**What is still unguarded** is what nobody has thought of: this table is a map of the fixtures, and
three of the defects found on 2026-09-10..11 lived in regimes it did not yet have rows for.

## Cases the rule deliberately gives up

| Situation | Given up | Why |
|---|---|---|
| A region arriving from below | Its label parks at the trailing edge instead of riding in at content speed | While a region arrives, its near edge moves with the rows and its far edge is the viewport, so anything centred in that window moves at HALF the region's speed. Visibility and content-speed arrival cannot both hold; visibility was judged worth more (2026-09-07) |
| Content taller than the band | The handover to "not moved" steps slightly | It bites on a value you are scrolling through, never on a label — the least visible discontinuity available |
