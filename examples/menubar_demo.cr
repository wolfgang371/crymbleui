require "../src/crymble-ui"

# Demo application showcasing menu bar features
class MenuBarDemo < CrymbleUI::App
    # State for checkable menu items
    state dark_mode : Bool = false
    state show_toolbar : Bool = true
    state show_statusbar : Bool = true

    # Counter for testing menu actions
    state action_count : Int32 = 0

    def build : CrymbleUI::Widget
        window("MenuBar Demo", 800, 600) do
            # Handle close request (X button, Alt+F4, etc.)
            on_closed do
                # Can save data, show dialogs, etc.
                puts "Close requested! Action count: #{@action_count}"
                # Call quit() to actually close
                self.quit
            end

            # Window menubar at top
            menubar do
                menu("File") do
                    menu_item("New", "^N") do
                        self.action_count += 1
                    end
                    menu_item("Open", "^O") do
                        self.action_count += 1
                    end
                    menu_item("Save", "^S") do
                        self.action_count += 1
                    end
                    separator
                    menu_item("Exit", "Alt+F4") do
                        # Quit the application
                        self.quit
                    end
                end

                menu("Edit") do
                    menu_item("Cut", "^X") do
                        self.action_count += 1
                    end
                    menu_item("Copy", "^C") do
                        self.action_count += 1
                    end
                    menu_item("Paste", "^V") do
                        self.action_count += 1
                    end
                end

                menu("View") do
                    menu_item("Dark Mode", checked: self.dark_mode) do
                        self.dark_mode = !self.dark_mode
                    end
                    menu_item("Show Toolbar", checked: self.show_toolbar) do
                        self.show_toolbar = !self.show_toolbar
                    end
                    menu_item("Show Statusbar", checked: self.show_statusbar) do
                        self.show_statusbar = !self.show_statusbar
                    end
                end

                menu("Help") do
                    menu_item("Documentation") do
                        self.action_count += 1
                    end
                    menu_item("About") do
                        self.action_count += 1
                    end
                end
            end

            # Main content
            vstack(spacing: 20.0) do
                cpu_monitor

                text("MenuBar Demo", font_scale: 5)
                text("Menu action count: #{@action_count}", font_scale: 1)

                text("View Options:", font_scale: 2)
                text("Dark Mode: #{self.dark_mode}", font_scale: 0)
                text("Show Toolbar: #{self.show_toolbar}", font_scale: 0)
                text("Show Statusbar: #{self.show_statusbar}", font_scale: 0)

                button("Reset Counter", shortcut: "^R") do
                    self.action_count = 0
                end
            end

            # Floating panel with its own menubar
            window_panel("Tools", x: 50.0, y: 100.0, width: 300.0, height: 250.0) do
                menubar do
                    menu("Options") do
                        menu_item("Settings") do
                            self.action_count += 1
                        end
                        menu_item("Preferences") do
                            self.action_count += 1
                        end
                    end

                    menu("Tools") do
                        menu_item("Export") do
                            self.action_count += 1
                        end
                        menu_item("Import") do
                            self.action_count += 1
                        end
                    end
                end

                vstack do
                    text("Panel with MenuBar", font_scale: 1)
                    text("Notice the menubar is", font_scale: -1)
                    text("below the panel title", font_scale: -1)
                end
            end
        end
    end
end

# Run the demo
CrymbleUI.run(MenuBarDemo.new)
