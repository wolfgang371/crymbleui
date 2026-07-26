#!/usr/bin/env bash
# SFML parity sweep gate (the ONE durable cross-backend instrument; mirrors cv-coherency.sh's style).
#
# Builds and runs spec/autotest/sfml_parity_autotest.cr — a single -Dcache_validation --release SFML
# binary that drives REAL rendering (Y-flip FBOs, real GPU sampling, real font/GC cost — the things
# headless TestRenderBackend is unfaithful to) through three structural configs (compound+sticky VM /
# TaskBoard merged-cell / plain ScrollView) x scroll magnitudes (diagonal, pure-V multi-recenter
# round-trip, pure-V deep past-extent, pure-H hops, Ctrl+0 reset, sub-recenter). Each phase asserts:
#   cv     — the immediate-mode validator ran on the viewport_cache content layer (stale-cache class);
#   GAP    — black-pixel counting on the sticky-inclusive window composite (window bg leaking through);
#   GARBLE — the scroll-invariant sticky band / returned round-trip must equal baseline (row39 class);
#   NON-VACUITY — real recenter/blit-shift/realloc counters + a non-empty rendered-layer sample set.
# Reverting a rendering fix (e.g. the vthumb blit-shift Y-flip, or a buffer_origin drift) makes it RED.
#
# shards has no autotest targets, so this compiles the .cr directly (the same convention the perf
# autotests document in their headers).
#
# Usage: source setup.sh && ./tools/sfml-parity.sh
# Exit: 0 = every phase green, 1 = at least one phase failed, 2 = the run could not be witnessed
#       (the X server aborted the process before a verdict — a cross-user DISPLAY=:0 GLX fault, not a
#       sweep result; retried a few times before giving up).
set -euo pipefail

BIN=/tmp/sfml_parity_bin
REPORT=/tmp/sfml_parity
SUMMARY="$REPORT/summary.txt"

crystal build --release -Dcache_validation spec/autotest/sfml_parity_autotest.cr -o "$BIN"

mkdir -p "$REPORT"
code=2
# A real sweep result (pass or fail) always writes a *** verdict *** to summary.txt and exits 0/1. A GLX
# X-server abort kills the process with NO verdict; that can be the driver's pre-existing FBO flakiness
# (green baseline completes within a few tries) OR a crash-class regression: the two proven historical
# faults (the 7e79842 blit_region recenter class and buffer_origin drift) manifest as EXACTLY this abort
# on this driver, deterministically. So retry only the no-verdict case (never a written verdict), and if
# it PERSISTS across all attempts exit 2 — which must be treated as a FAILURE to investigate (rebuild at
# the last-known-good commit to discriminate env from regression), never waved through.
for attempt in 1 2 3; do
  : > "$SUMMARY"
  set +e
  DISPLAY=:0 timeout 180 "$BIN" > "$REPORT/run.log" 2>&1
  code=$?
  set -e
  if grep -q '\*\*\* SWEEP' "$SUMMARY" 2>/dev/null; then
    break
  fi
  echo "sfml-parity: attempt $attempt produced no verdict (GLX abort: env flake OR crash-class regression, exit=$code) — retrying" >&2
  sleep 4
  code=2
done

echo "----------------------------------------------------------------------"
cat "$SUMMARY" 2>/dev/null || echo "sfml-parity: no summary produced (see $REPORT/run.log)"
echo "----------------------------------------------------------------------"
exit "$code"
