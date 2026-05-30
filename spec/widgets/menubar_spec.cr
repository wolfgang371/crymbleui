require "../spec_helper"

describe CrymbleUI::MenuBar do
    describe ".new" do
        it "creates a menubar with default values" do
            menubar = CrymbleUI::MenuBar.new
            menubar.should_not be_nil
        end
    end

    describe "#measure" do
        it "returns fixed height and full width" do
            menubar = CrymbleUI::MenuBar.new
            constraints = CrymbleUI::BoxConstraints.new(max_width: 800.0, max_height: 600.0)
            size = menubar.measure(constraints)

            size.width.should eq(800.0)
            size.height.should eq(menubar.menubar_height)
        end
    end

    describe "#layout" do
        it "lays out menu items horizontally" do
            menubar = CrymbleUI::MenuBar.new

            # Add two menus
            menu1 = CrymbleUI::Menu.new("File")
            menu2 = CrymbleUI::Menu.new("Edit")
            menubar.add_child(menu1)
            menubar.add_child(menu2)

            constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800.0, 600.0))
            menubar.layout(constraints, CrymbleUI::Vec2.zero)

            # First menu should be at x=0
            menu1.bounds.x.should eq(0.0)

            # Second menu should be after first menu
            menu2.bounds.x.should eq(menu1.bounds.width)
        end
    end

    describe "#to_primitives" do
        it "generates two primitives with no menus (full background + border)" do
            menubar = CrymbleUI::MenuBar.new
            bounds = CrymbleUI::Rect.new(0, 0, 800, 28)

            primitives = menubar.to_primitives(bounds)

            primitives.size.should eq(2)
            primitives[0].should be_a(CrymbleUI::FillRect)  # Background
            primitives[1].should be_a(CrymbleUI::FillRect)  # Border
        end

        it "full background primitive has correct bounds when no menus" do
            bg_color = CrymbleUI::Color.new(250, 250, 250, 255)
            menubar = CrymbleUI::MenuBar.new(background_color: bg_color)
            bounds = CrymbleUI::Rect.new(10, 20, 800, 28)

            primitives = menubar.to_primitives(bounds)
            background = primitives[0].as(CrymbleUI::FillRect)

            # Widget-local coordinates: origin is (0,0)
            # Background should be full bounds minus border height
            background.bounds.x.should eq(0.0)
            background.bounds.y.should eq(0.0)
            background.bounds.width.should eq(800.0)
            background.bounds.height.should eq(27.0)  # 28 - 1 (BORDER_WIDTH)
            background.color.should eq(bg_color)
        end

        it "generates background in empty space when menus present" do
            menubar = CrymbleUI::MenuBar.new

            # Add menus and layout them
            menu1 = CrymbleUI::Menu.new("File")
            menu2 = CrymbleUI::Menu.new("Edit")
            menubar.add_child(menu1)
            menubar.add_child(menu2)

            constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800.0, 600.0))
            menubar.layout(constraints, CrymbleUI::Vec2.zero)

            bounds = CrymbleUI::Rect.new(0, 0, 800, 28)
            primitives = menubar.to_primitives(bounds)

            # Should have background (empty space) + border
            primitives.size.should eq(2)
            background = primitives[0].as(CrymbleUI::FillRect)

            # Background should start after last menu
            last_menu_end = menu2.bounds.x + menu2.bounds.width
            background.bounds.x.should eq(last_menu_end)
            background.bounds.width.should eq(800.0 - last_menu_end)
        end

        it "border primitive has correct bounds and color" do
            border_color = CrymbleUI::Color.new(200, 200, 200, 255)
            menubar = CrymbleUI::MenuBar.new(border_color: border_color)
            bounds = CrymbleUI::Rect.new(10, 20, 800, 28)

            primitives = menubar.to_primitives(bounds)
            border = primitives[1].as(CrymbleUI::FillRect)

            # Widget-local coordinates: origin is (0,0)
            # Border is 1px high at bottom
            border.bounds.x.should eq(0.0)
            border.bounds.y.should eq(27.0)  # 28 - 1 (widget-local)
            border.bounds.width.should eq(800.0)
            border.bounds.height.should eq(1.0)
            border.color.should eq(border_color)
        end

        it "uses custom colors" do
            bg_color = CrymbleUI::Color.new(100, 100, 100, 255)
            border_color = CrymbleUI::Color.new(50, 50, 50, 255)
            menubar = CrymbleUI::MenuBar.new(background_color: bg_color, border_color: border_color)
            bounds = CrymbleUI::Rect.new(0, 0, 800, 28)

            primitives = menubar.to_primitives(bounds)

            background = primitives[0].as(CrymbleUI::FillRect)
            border = primitives[1].as(CrymbleUI::FillRect)

            background.color.should eq(bg_color)
            border.color.should eq(border_color)
        end

    end

    describe "primitive caching" do
        it "caches primitives with Dynamic policy (default)" do
            menubar = CrymbleUI::MenuBar.new
            bounds = CrymbleUI::Rect.new(0, 0, 800, 28)

            # First call generates
            primitives1 = menubar.get_primitives(bounds)
            menubar.clear_render_state_recursive  # Mark clean

            # Second call returns cached
            primitives2 = menubar.get_primitives(bounds)

            primitives1.should be(primitives2)  # Same object
        end

        it "regenerates when colors change" do
            menubar = CrymbleUI::MenuBar.new
            bounds = CrymbleUI::Rect.new(0, 0, 800, 28)

            primitives1 = menubar.get_primitives(bounds)
            bg1 = primitives1[0].as(CrymbleUI::FillRect)

            # background_color= calls mark_needs_render
            new_color = CrymbleUI::Color.new(255, 0, 0, 255)
            menubar.background_color = new_color

            primitives2 = menubar.get_primitives(bounds)
            bg2 = primitives2[0].as(CrymbleUI::FillRect)

            bg1.color.should_not eq(new_color)
            bg2.color.should eq(new_color)
        end

        it "regenerates when border color changes" do
            menubar = CrymbleUI::MenuBar.new
            bounds = CrymbleUI::Rect.new(0, 0, 800, 28)

            primitives1 = menubar.get_primitives(bounds)
            border1 = primitives1[1].as(CrymbleUI::FillRect)

            # border_color= calls mark_needs_render
            new_color = CrymbleUI::Color.new(0, 255, 0, 255)
            menubar.border_color = new_color

            primitives2 = menubar.get_primitives(bounds)
            border2 = primitives2[1].as(CrymbleUI::FillRect)

            border1.color.should_not eq(new_color)
            border2.color.should eq(new_color)
        end
    end
end

describe CrymbleUI::Menu do
    describe ".new" do
        it "creates a menu with a label" do
            menu = CrymbleUI::Menu.new("File")
            menu.label_text.should eq("File")
        end
    end

    describe "#measure" do
        it "sizes based on label width plus padding" do
            menu = CrymbleUI::Menu.new("File")
            constraints = CrymbleUI::BoxConstraints.new(max_width: 800.0, max_height: 28.0)
            size = menu.measure(constraints)

            size.height.should eq(28.0)
            # Width = text width + padding*2 (at least padding*2 = 20.0 even with zero text width)
            size.width.should be >= 20.0
        end
    end
end

describe CrymbleUI::MenuItem do
    describe ".new" do
        it "creates a menu item with label only" do
            item = CrymbleUI::MenuItem.new("New") { }
            item.label_text.should eq("New")
            item.shortcut.should be_nil
            item.checked.should be_false
        end

        it "creates a menu item with label and shortcut" do
            item = CrymbleUI::MenuItem.new("Copy", "Ctrl+C") { }
            item.label_text.should eq("Copy")
            item.shortcut.should eq("Ctrl+C")
        end

        it "creates a checkable menu item" do
            item = CrymbleUI::MenuItem.new("Dark Mode", checked: true) { }
            item.checked.should be_true
        end
    end

    describe "#measure" do
        it "returns fixed height and calculates width from content" do
            item = CrymbleUI::MenuItem.new("New") { }
            constraints = CrymbleUI::BoxConstraints.new
            size = item.measure(constraints)

            size.height.should eq(item.item_height)
            # Width = check_width(16) + label_width + spacing + shortcut_width + padding*2
            size.width.should be > 0.0
        end
    end

    describe "#trigger_click" do
        it "calls the click callback" do
            clicked = false
            item = CrymbleUI::MenuItem.new("Test") { clicked = true }

            item.trigger_click
            clicked.should be_true
        end
    end

    describe "checkable items" do
        it "auto-detects checkable when checked parameter is provided" do
            item_true = CrymbleUI::MenuItem.new("Option", checked: true) { }
            item_true.checkable.should be_true

            item_false = CrymbleUI::MenuItem.new("Option", checked: false) { }
            item_false.checkable.should be_true
        end

        it "is not checkable when checked parameter is nil" do
            item = CrymbleUI::MenuItem.new("Action") { }
            item.checkable.should be_false
        end

        it "keeps menu open when clicking checkable item (via trigger_click)" do
            # Create Menu -> Popup -> MenuItem hierarchy
            menu = CrymbleUI::Menu.new("View")

            # Create checkable item
            clicked = false
            item = CrymbleUI::MenuItem.new("Dark Mode", checked: false) { clicked = true }

            # Set up hierarchy: Menu -> Popup -> MenuItem
            popup = CrymbleUI::Popup.new(width: 150.0, height: 100.0)
            popup.add_child(item)
            menu.add_child(popup)

            # Open menu
            menu.on_click
            menu.open?.should be_true

            # Click checkable item (using trigger_click, which is what the UI calls)
            item.trigger_click

            # Callback should be called
            clicked.should be_true

            # Menu should still be open (checkable items keep menu open)
            menu.open?.should be_true
        end

        it "closes menu when clicking non-checkable item (via trigger_click)" do
            # Create Menu -> Popup -> MenuItem hierarchy
            menu = CrymbleUI::Menu.new("File")

            # Create non-checkable action item
            clicked = false
            item = CrymbleUI::MenuItem.new("New") { clicked = true }

            # Set up hierarchy: Menu -> Popup -> MenuItem
            popup = CrymbleUI::Popup.new(width: 150.0, height: 100.0)
            popup.owner = menu  # Required for menu closing
            popup.add_child(item)
            menu.add_child(popup)

            # Open menu
            menu.on_click
            menu.open?.should be_true

            # Click non-checkable item (using trigger_click, which is what the UI calls)
            item.trigger_click

            # Callback should be called
            clicked.should be_true

            # Menu should be closed (non-checkable items close menu)
            menu.open?.should be_false
        end
    end

    describe "menu click behavior" do
        it "clicking an open menu closes it" do
            menu = CrymbleUI::Menu.new("File")

            # First click opens the menu
            menu.on_click
            menu.open?.should be_true

            # Second click on same menu closes it
            menu.on_click
            menu.open?.should be_false
        end
    end

    describe "reconciliation preserves menu state" do
        it "keeps menu open across rebuilds when clicking checkable item" do
            # Create old menu hierarchy (as it would be in first build)
            old_menu = CrymbleUI::Menu.new("View")
            old_item = CrymbleUI::MenuItem.new("Dark Mode", checked: false) { }
            old_popup = CrymbleUI::Popup.new(width: 150.0, height: 100.0)
            old_popup.add_child(old_item)
            old_menu.add_child(old_popup)

            # Open the menu
            old_menu.on_click
            old_menu.open?.should be_true

            # Create new menu hierarchy (as it would be created in rebuild after state change)
            new_menu = CrymbleUI::Menu.new("View")
            new_item = CrymbleUI::MenuItem.new("Dark Mode", checked: true) { }  # State changed
            new_popup = CrymbleUI::Popup.new(width: 150.0, height: 100.0)
            new_popup.add_child(new_item)
            new_menu.add_child(new_popup)

            # Simulate reconciliation (copy state from old to new)
            new_menu.copy_state_from(old_menu)

            # Menu should still be open after reconciliation
            new_menu.open?.should be_true
        end
    end

    describe "shortcut alignment" do
        it "sets max_label_width on all menu items for consistent shortcut positioning" do
            menu = CrymbleUI::Menu.new("File")

            # Create menu items with different label lengths but all with shortcuts
            item1 = CrymbleUI::MenuItem.new("New", "Ctrl+N") { }
            item2 = CrymbleUI::MenuItem.new("Open", "Ctrl+O") { }
            item3 = CrymbleUI::MenuItem.new("Save", "Ctrl+S") { }

            # Simulate DSL - menu captures items as children
            menu.add_child(item1)
            menu.add_child(item2)
            menu.add_child(item3)

            # Layout menu to trigger measurement
            constraints = CrymbleUI::BoxConstraints.new(max_height: 28.0)
            menu.layout(constraints, CrymbleUI::Vec2.zero)

            # Open menu (this should calculate and set max_label_width)
            menu.on_click

            # All items should have the same max_label_width
            item1.max_label_width.should be > 0
            item2.max_label_width.should eq(item1.max_label_width)
            item3.max_label_width.should eq(item1.max_label_width)

            # max_label_width should be at least as wide as the widest label
            max_width = [item1.label_width, item2.label_width, item3.label_width].max
            item1.max_label_width.should eq(max_width)
        end
    end
end

describe CrymbleUI::Separator do
    describe "#measure" do
        it "returns fixed height and minimal natural width" do
            sep = CrymbleUI::Separator.new
            constraints = CrymbleUI::BoxConstraints.new(max_width: 200.0)
            size = sep.measure(constraints)

            size.height.should eq(CrymbleUI::Separator::SEPARATOR_HEIGHT)
            # Separator returns 0 natural width so it doesn't dominate its
            # column in auto-sizing layouts (see separator.cr for details).
            # Visual stretching happens in #perform_layout, not #measure.
            size.width.should eq(0.0)
        end
    end
end
