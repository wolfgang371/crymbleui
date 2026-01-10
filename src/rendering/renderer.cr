require "../core/types"
require "./draw_primitive"

module CrymbleUI
  # Abstract renderer interface
  # Allows swapping between SFML (real) and Test (headless) renderers
  module Renderer
    # Render a single frame of the app
    abstract def render_frame(app : App)

    # Render primitives directly (for direct drawing)
    abstract def render_primitives(primitives : Array(DrawPrimitive))

    # Render a layer to its texture
    abstract def render_layer(layer : Layer)

    # Check if renderer is running (for event loops)
    abstract def running? : Bool

    # Get scheduler (for task scheduling)
    abstract def scheduler : Scheduler

    # Get shortcut manager (for keyboard shortcuts)
    abstract def shortcut_manager : ShortcutManager
  end
end
