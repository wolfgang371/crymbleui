module CrymbleUI
  # A widget that an outside-click or ESC tears down — the menu/menubar dismissal set.
  # `App#close_all_menus` dismisses every `Dismissable` in the widget tree; `dismiss_overlay`
  # returns whether it was actually open/active, so the caller can report "something closed".
  #
  # Asked via `is_a?(Dismissable)` — the capability-module pattern (like `Draggable`) — so the
  # generic App never type-checks `Menu`/`MenuBar`.
  module Dismissable
    # Tear this overlay down (close the menu / deactivate the menubar). Returns true iff it
    # was open/active (i.e. this dismissal actually closed something).
    abstract def dismiss_overlay : Bool
  end

  # A click-interactive overlay SURFACE — a `Popup` or an open `Menu`. A mouse-down landing
  # inside one is an interaction with that surface, NOT a dismiss gesture, so it must not close
  # other menus (`App#is_inside_overlay_surface?`).
  #
  # Deliberately distinct from `Dismissable`: a `MenuBar` is dismissable but is NOT a surface
  # (clicking its background dismisses open menus), and a standalone `Popup` is a surface but is
  # not menu-dismissable. A pure marker — membership is the whole signal.
  module OverlaySurface
  end
end
