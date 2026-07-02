#!/usr/bin/env bash
# cache-coherency gate (the dual renderer, used consequently).
#
# Runs the matrix / ScrollView coherency specs under -Dcache_validation. In that mode the
# immediate-mode validator re-renders each viewport-cache CONTENT layer from scratch via
# to_primitives() and compares it pixel-by-pixel against the cached buffer; spec_helper's
# after_each fails the example on any divergence — i.e. the exact stale-cache ghost class.
# Reverting any of the cache-invalidation fixes makes this script go red.
#
# Scope notes:
#   - Auto-covers viewport_cache CONTENT layers. Sticky layers are excluded — render_layer_immediate
#     mis-positions sticky cells (a Phase-0 follow-up), so they'd be false positives.
#   - NON-matrix overlay/window layers opt in per-layer via Layer#cv_validate (the validator condition
#     is `(viewport_cache && !sticky) || cv_validate`). cv_non_matrix_oracle_spec proves it catches a
#     stale cache on such a layer (synthetic-color widgets — no AA jitter).
#   - Perf-counter specs are excluded — cv's 2nd ground-truth render per frame inflates the
#     render counters, which is meaningless to assert on.
#
# Also built with -Dverify_bounds: the viewport_cache buffer_origin invariant (whole-valued +
# always-fitting, one reader / one writer) is a raise at the writer and both composite seams. This is the
# permanent gate for that invariant on the ScrollView/VMatrix specs — one build carries both flags.
#
# Usage: source setup.sh && ./tools/cv-coherency.sh
set -euo pipefail

crystal spec -Dcache_validation -Dverify_bounds \
  spec/rendering/cache_validation_spec.cr \
  spec/rendering/cache_validation_widen_spec.cr \
  spec/rendering/cv_non_matrix_oracle_spec.cr \
  spec/rendering/scroll_view_resize_cv_spec.cr \
  spec/autotest/ \
  spec/widgets/virtual_matrix_rendering_spec.cr \
  spec/widgets/virtual_matrix_black_rows_spec.cr \
  spec/widgets/virtual_matrix_sticky_ghosting_spec.cr \
  spec/widgets/virtual_matrix_blit_shift_spec.cr \
  spec/widgets/virtual_matrix_scrollbar_sync_spec.cr \
  spec/widgets/virtual_matrix_sticky_scroll_sync_spec.cr \
  spec/widgets/virtual_matrix_hscroll_drag_desync_spec.cr \
  spec/widgets/virtual_matrix_ruler_scroll_spec.cr \
  spec/widgets/virtual_matrix_content_offset_spec.cr \
  spec/widgets/virtual_matrix_row_gap_spec.cr \
  spec/widgets/virtual_matrix_sticky_row_hscroll_spec.cr \
  spec/widgets/virtual_matrix_tab_roundrobin_spec.cr \
  spec/widgets/virtual_matrix_text_input_spec.cr \
  spec/widgets/virtual_matrix/scroll_render_spec.cr \
  spec/widgets/virtual_matrix/cursor_spec.cr \
  spec/widgets/virtual_matrix/cursor_overlay_spec.cr \
  spec/widgets/virtual_matrix/sticky_snap_spec.cr \
  spec/widgets/virtual_matrix/tutorial22_bugs_spec.cr \
  spec/widgets/virtual_matrix/tab_wraparound_ghost_spec.cr
