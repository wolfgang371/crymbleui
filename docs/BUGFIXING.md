# Causality sequence

root cause -> possible internal inconsistency -> symptom1 -> symptom2 -> etc.

actually, this is oversimplified - in a complex system (like we have) we might also suffer from _multiple_ root causes for one symptom.
this understanding is important, since single bugfixes will not work in such setups!

# Execution models

- I will typically use the SFML based visual system
- you will typically use the headless test system

both are supposed to behave identically, but every now and then a difference will show up.

## How to deal with differences in execution models

we always need to have a failing test case first.

(a) ideally this is a headless test (which will be commited later)
(b) if not possible w/ a headless test, we temporarily (i.e. not to be commited) use an automated SFML test instead
    - this will be used to also figure out the difference between the two execution models
    - and hence also be used to align the execution models
    - and to create a failing headless test (a) instead later

# Implementation sequence when hunting for a bug

1. we always need to have a failing test case first (see "How to deal with differences in execution models")
1. based on an automated test we can do further investigation
    - reasoning and/or
    - either instrumentation
1. identify (intermediate) hypothesis
1. it is important to construct an FTA (fault tree analysis)
    - observed symptom is root
    - nodes on next layer: either AND or OR
    - nodes on next layer: (intermediate) hypothesis
    - ... continue
1. in the course of investigation we will confirm (intermediate) hypothesis - or falsify
1. it is important to store the continuously developed FTA in such a way that it survives auto-compact, e.g. by continuously writing it to the plan file
1. at the end we have one sub-tree of the FTA as the proper FTA (which we can store in the commit message)
1. when we succeed we
    (a) re-confirm the bug is still detected w/ our headless test w/o the fix(es) being in place
    (b) confirm the bug is gone w/ our fix(es) in place
    (c) we have no regressions
    (d) remove all instrumentation
1. commit

# Lessons learned

## Layer-specific instrumentation early

When a bug manifests visually (e.g. black pixels, rendering gaps), add per-layer PNG dumps or pixel inspection **before** reasoning about code paths. In the Bug 2 investigation, content_layer PNGs immediately showed truncated compound cells — this was the smoking gun. Without them, many phases were spent suspecting compositor/buffer_origin/blit code.

**Rule**: If the symptom is visual, make it visible per-layer first. Reasoning without visual evidence in a multi-layer system wastes time.

## Overlapping root causes hide progress

Bug 2 had two independent root causes (compound cell sizing + buffer origin drift) producing the same symptom (black pixels after hscroll round-trip). Fixing one didn't reduce the symptom because the other still produced it. This led to falsely reverting correct fixes.

**Rule**: When a fix doesn't eliminate the symptom, check whether a second root cause exists before reverting. Use the "hot candidates" combination testing approach documented above.

## Question uniform code paths across architectural boundaries

Bug A happened because WU3 visible-size shrinking was applied uniformly to all compound cells. But content cells and sticky cells have fundamentally different coordinate models (fixed content-space vs viewport-relative). The fix was a two-line guard: `next if row >= sticky_rows && col >= sticky_cols`.

**Rule**: When code applies the same transformation to widgets on different layers or in different coordinate spaces, verify the transformation is correct for each case. Uniform application across architectural boundaries is a common source of subtle bugs.

## Assert invariants at the boundary, not just the output

A test asserting "content compound cell width == calculate_merged_width regardless of scroll position" would have caught Bug A at introduction time. Instead, the only tests verified final pixel output, which required both bugs to be fixed simultaneously.

**Rule**: Write invariant tests for intermediate state (cell sizes, positions, layer contents), not just end-to-end pixel tests. These catch bugs earlier and isolate root causes.
