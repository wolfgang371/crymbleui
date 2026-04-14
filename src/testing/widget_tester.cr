require "../core/widget"
require "../core/app"
require "../core/types"

module CrymbleUI
    module Testing
        # Widget testing utility for headless testing of widget trees without rendering
        class WidgetTester
            getter app : App?
            property window_size : Size

            def initialize(@window_size : Size = Size.new(800.0, 600.0))
                @app = nil
            end

            # Build and layout the app (no window needed - primitives are just data)
            def pump(app : App)
                # Build widget tree
                app.build_tree

                # Layout the tree
                if root = app.root
                    constraints = BoxConstraints.loose(@window_size)
                    root.layout(constraints, Vec2.new(0.0, 0.0))
                end

                @app = app
            end

            # Find widget by ID
            def find(id : String) : Widget?
                @app.try &.find(id)
            end

            # Find widget by path ID
            def find_by_path(path : String) : Widget?
                @app.try &.find_by_path(path)
            end

            # Find all widgets matching condition
            def find_all(&block : Widget -> Bool) : Array(Widget)
                if app = @app
                    app.find_all(&block)
                else
                    [] of Widget
                end
            end

            # Trigger click on a widget
            def tap(widget : Widget)
                widget.trigger_click
                # Rebuild and re-layout if needs layout
                if app = @app
                    if app.needs_rebuild?
                        app.rebuild
                        # Re-layout the new tree
                        if root = app.root
                            constraints = BoxConstraints.loose(@window_size)
                            root.layout(constraints, Vec2.new(0.0, 0.0))
                        end
                    end
                end
            end

            # Trigger click on widget by ID
            def tap(id : String)
                if widget = find(id)
                    tap(widget)
                else
                    raise "Widget with id '#{id}' not found"
                end
            end

            # Get the root widget
            def root : Widget?
                @app.try &.root
            end

            # Verify that a widget with given ID exists
            def exists?(id : String) : Bool
                find(id) != nil
            end

            # Get text content from a Text widget
            def text(id : String) : String?
                if widget = find(id)
                    if widget.is_a?(CrymbleUI::Text)
                        widget.text
                    end
                end
            end
        end
    end
end
