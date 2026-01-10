# Causality sequence

root cause -> possible internal inconsistency -> symptom1 -> symptom2 -> etc.

actually, this is oversimplified - in a complex system (like we have) we might also suffer from _multiple_ root causes for one symptom.
this understanding is important, since single bugfixes will not work in such setups!

## How to deal multiple root causes for a single failure

we have to identify a set of "hot candidates" (e.g. n) and test all combinations (e.g. 2**n) - if all else fails.
in any case we need to keep track of all those "hot candidates" in the plan and note...
- which fix is currently implemented
- and which combinations already have been tested (successfully or not)

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
1. identify hypothesis
    - identification of possible root causes ("hot candidates")
1. try to fix these (see "How to deal multiple root causes for a single failure")
1. when we succeed we
    (a) re-confirm the bug is still detected w/ our headless test w/o the fix(es) being in place
    (b) confirm the bug is gone w/ our fix(es) in place
    (c) we have no regressions
    (d) remove all instrumentation
1. commit
