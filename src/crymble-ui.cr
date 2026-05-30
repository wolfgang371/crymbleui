# CrymbleUI - Declarative GUI framework for Crystal
# Main entry point - require this file to use CrymbleUI

# Core types and foundation
require "./core/types"
require "./core/theme"
require "./core/scheduler"
require "./core/widget"
require "./core/draggable"
require "./core/drop_target"
require "./core/app"

# Widgets
require "./widgets/text"
require "./widgets/button"
require "./widgets/window"
require "./widgets/window_panel"
require "./widgets/scroll_view"
require "./widgets/virtual_matrix"
require "./widgets/simple_matrix"
require "./widgets/dir_browser"
require "./widgets/virtual_grid_base"
require "./widgets/tree_node"

# Layout containers
require "./layout/vstack"
require "./layout/hstack"
require "./layout/flow"
require "./layout/decorated_container"

# Rendering
require "./rendering/sfml_paint_context"
require "./rendering/sfml_renderer"
require "./rendering/cache_validation"

# DSL and testing
require "./dsl/builder"
require "./testing/widget_tester"

# Main module-level convenience method
module CrymbleUI
    VERSION = {{ `shards version "#{__DIR__}/.."`.chomp.stringify }}

    @@renderer : SFMLRenderer? = nil

    # Access the renderer (for testing/debugging)
    def self.renderer : SFMLRenderer?
        @@renderer
    end

    # Run an application with automatic renderer creation
    # Extracts window configuration from the app's build() method
    #
    # Usage:
    #   CrymbleUI.run(MyApp.new)
    def self.run(app : App)
        # Build the widget tree
        app.build_tree

        # Get the root widget (should be a Window)
        root = app.root
        raise "App.build() must return a Window widget" unless root.is_a?(Window)

        # Extract window configuration
        window_widget = root.as(Window)

        # Create renderer with window settings
        @@renderer = SFMLRenderer.new(
            width: window_widget.width,
            height: window_widget.height,
            title: window_widget.title
        )

        # Run the application
        @@renderer.not_nil!.run(app)
    end
end
