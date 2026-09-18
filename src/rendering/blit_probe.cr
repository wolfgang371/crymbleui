# Diagnostic sink for the sticky blit path. Compiled in ONLY by -Dprobe; without it the module and
# every call site vanish, so the shipped library is untouched.
#
# It exists because a layer-level counter could not answer the question. The sticky garbling hunt
# asserted "cells moved => Layer#clear_rev advanced", which is false: the blit path activates a
# layer with mark_needs_full_render (bumps @render_rev) and clears the buffer through the fast path
# in render_layer, never touching clear_rev. The counter sat one level ABOVE the mechanism and
# produced a false positive. This sits inside it.
#
# The host installs a sink so the lines land in the app's own log; stderr is useless in a -Dgui
# build on Windows, where the report came from.
{% if flag?(:probe) %}
module CrymbleUI
  module BlitProbe
    @@sink : Proc(String, Nil)? = nil

    def self.sink=(s : Proc(String, Nil)?) : Nil
      @@sink = s
    end

    def self.on? : Bool
      !@@sink.nil?
    end

    def self.emit(line : String) : Nil
      @@sink.try &.call(line)
    rescue
      # an instrument must never take down what it measures
    end
  end
end
{% end %}
