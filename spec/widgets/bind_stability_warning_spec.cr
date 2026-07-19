require "../spec_helper"
require "../../src/widgets/text_input"
require "../../src/widgets/window"

# bind: STABILITY GUARD. A two-way-bound widget must adopt the SAME app-owned Source each build (a
# stable ivar re-passed each build), NOT a fresh Source.new(...) created inside build() — else every
# reconcile re-adopts a new cell and edits + cross-widget sharing silently break. The guard WARNS
# (once) after the bound Source's identity changes on 2 CONSECUTIVE reconciles: that is the
# fresh-per-build signature, while a legitimate one-time rebind (identity changes once, then settles)
# and an UNBOUND input (which legitimately owns a fresh Source each build) must NOT trip it.

# ANTI-PATTERN: a fresh Source every build (the footgun this guard catches).
private class FreshSourceApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Fresh", 400, 300) do
      text_input(bind: CrymbleUI::Source(String).new("x"), id: "a")
    end
  end
end

# CORRECT: a stable app-owned Source re-passed each build.
private class StableSourceApp < CrymbleUI::App
  getter src : CrymbleUI::Source(String)

  def initialize(@src : CrymbleUI::Source(String))
    super()
  end

  def build : CrymbleUI::Widget
    window("Stable", 400, 300) do
      text_input(bind: @src, id: "a")
    end
  end
end

# LEGITIMATE one-time rebind: Source A, then swap to B once, then stable on B.
private class OneTimeSwapApp < CrymbleUI::App
  property use_b = false

  def initialize(@a : CrymbleUI::Source(String), @b : CrymbleUI::Source(String))
    super()
  end

  def build : CrymbleUI::Widget
    window("Swap", 400, 300) do
      text_input(bind: (@use_b ? @b : @a), id: "a")
    end
  end
end

# UNBOUND input: owns a fresh Source each build by design — must be exempt from the guard.
private class UnboundApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Unbound", 400, 300) do
      text_input(value: "x", id: "a")
    end
  end
end

describe "bind: stability guard (fresh-Source-per-build)" do
  it "WARNS after a bound Source changes identity on 2 consecutive rebuilds" do
    CrymbleUI::Widget.reset_bind_stability_warnings
    app = FreshSourceApp.new
    app.build_tree
    CrymbleUI::Widget.bind_stability_warnings.should eq(0) # initial build: no reconcile yet
    app.rebuild                                            # reconcile 1: fresh != old -> streak 1
    CrymbleUI::Widget.bind_stability_warnings.should eq(0)
    app.rebuild                                            # reconcile 2: streak 2 -> WARN once
    CrymbleUI::Widget.bind_stability_warnings.should eq(1)
    app.rebuild                                            # reconcile 3: streak 3 -> no repeat
    CrymbleUI::Widget.bind_stability_warnings.should eq(1)
  end

  it "does NOT warn for a STABLE app-owned Source across many rebuilds" do
    CrymbleUI::Widget.reset_bind_stability_warnings
    app = StableSourceApp.new(CrymbleUI::Source(String).new("x"))
    app.build_tree
    5.times { app.rebuild }
    CrymbleUI::Widget.bind_stability_warnings.should eq(0)
  end

  it "does NOT warn for a legitimate ONE-TIME rebind (identity changes once, then settles)" do
    CrymbleUI::Widget.reset_bind_stability_warnings
    app = OneTimeSwapApp.new(CrymbleUI::Source(String).new("a"), CrymbleUI::Source(String).new("b"))
    app.build_tree
    app.rebuild            # A -> A: stable, streak 0
    app.use_b = true
    app.rebuild            # A -> B: one-time swap, streak 1 (below the warn threshold)
    3.times { app.rebuild } # B -> B: stable, streak resets to 0
    CrymbleUI::Widget.bind_stability_warnings.should eq(0)
  end

  it "does NOT warn for an UNBOUND input that owns a fresh Source each build" do
    CrymbleUI::Widget.reset_bind_stability_warnings
    app = UnboundApp.new
    app.build_tree
    5.times { app.rebuild }
    CrymbleUI::Widget.bind_stability_warnings.should eq(0)
  end
end
