require "./test_renderer"
require "./keys"
require "../widgets/window"
require "../widgets/statusbar"
require "../widgets/button"
require "../widgets/checkbox"
require "../widgets/menu_item"
require "../widgets/text_input"
require "../widgets/virtual_matrix"
require "../widgets/dir_browser"

module CrymbleUI
  module Testing
    # Drives an app the way a use case reads: by widget id, headless. See docs/TESTING.md.
    #
    #     ui = CrymbleUI::Testing::Driver.new(MyApp.new)
    #     ui.right_click "row_3"
    #     ui.click "ctx_rename"
    #     ui.type "renamer_name", "Area"
    #     ui.press "Enter"
    #     ui.text("statusbar").should contain "Renamed"
    #
    # TRIGGER SEMANTICS. An act runs what real input runs AROUND the handler - close the popups and
    # menus a click there would close, bring the containing panel to front, call the handler,
    # settle - and skips only finding the widget by position. What that leaves out (hit-testing,
    # occlusion, drag thresholds, point spaces) stays with the coordinate specs that own it - except
    # for the acts that go by position: hover, and click_cell / drag_cell (a grid acts on the cell
    # under the mouse).
    class Driver
      getter app : App
      getter renderer : TestRenderer

      # The `within` scopes, outermost first; each is resolved inside the one before it. A scope
      # with an id is kept as the id, so a rebuild that replaces the instance does not strand it.
      @scopes = [] of String | Widget
      # The clock `advance` has reached. Never behind the real one: widgets schedule timers from
      # Time.instant, and a lagging clock would miss them.
      @now : Time::Instant
      @reports : Array(String)? = nil # set only inside expect_reported
      # Per panel id, the x of press_title's previous press - the next one lands far from it.
      @title_presses = {} of String => Float64

      def initialize(@app : App, width : Int32 = 1200, height : Int32 = 800)
        @renderer = TestRenderer.new(width, height)
        # As SFMLRenderer#run starts: handlers reach the app through Widget.app, and the tree is
        # built before the first frame.
        Widget.app = @app
        @app.build_tree
        @now = Time.instant
        settle
      end

      # Render until nothing changes. A requested rebuild is applied by the first frame.
      def settle : Nil
        @renderer.settle_rendering(@app)
      end

      # === Lookup ===

      # The widget with this id: the window tree first, then its overlays (popups, context menus) -
      # everything a user can see. Raises, naming the ids that look like it.
      def find(id : String) : Widget
        find?(id) || raise ArgumentError.new(missing(id))
      end

      def present?(id : String) : Bool
        !find?(id).nil?
      end

      # The one widget whose id starts with `prefix` and has no ancestor that also does - a dialog
      # found by its kind (`only("renamer_")`), not the `renamer_name` field inside it.
      def only(prefix : String) : Widget
        matches = all { |w| w.id.try(&.starts_with?(prefix)) || false }
        tops = matches.reject { |w| ancestors(w).any? { |a| matches.includes?(a) } }
        return tops.first if tops.size == 1
        found = tops.compact_map(&.id).join(", ")
        raise ArgumentError.new("#{tops.size} widgets start with \"#{prefix}\"#{found.empty? ? "" : ": #{found}"}")
      end

      # Scope every lookup inside the block to one subtree (by id, or a widget).
      def within(target : String | Widget, &) : Nil
        scope = target.is_a?(Widget) ? (target.id || target) : target
        find(scope) if scope.is_a?(String) # fail now, not on the first lookup inside
        @scopes.push(scope)
        begin
          yield
        ensure
          @scopes.pop
        end
      end

      # === Acts ===

      def click(id : String) : Nil
        widget = find(id)
        refuse_matrix(ancestors(widget), "click", id, CLICK_CELL_HINT)
        raise ArgumentError.new("\"#{id}\" is disabled") unless widget.enabled?
        act(widget) { widget.trigger_click }
      end

      def right_click(id : String) : Nil
        widget = find(id)
        refuse_matrix(handler_chain(widget), "right_click", id, RIGHT_CLICK_CELL_HINT)
        act(widget) do
          raise Refusal.new("no right-click handler at or above \"#{id}\"") unless widget.trigger_right_click
        end
      end

      # Drag the Draggable at or above `id` onto the DropTarget at or above `target_id` (at or above,
      # as real input finds a draggable from the widget under the mouse). The drop lands at the
      # target's centre. Raises with the reason when the target refuses.
      def drag(id : String, onto target_id : String) : Nil
        source, target = drag_ends(id, target_id)
        act(source) do
          if reason = @app.drag_manager.drag_onto(source, target, target.viewport_bounds.center)
            raise Refusal.new("dragging \"#{id}\" onto \"#{target_id}\" was refused: #{reason}")
          end
        end
      end

      # Whether `drag(id, onto: target_id)` would land - for asserting a refusal.
      def can_drop?(id : String, onto target_id : String) : Bool
        source, target = drag_ends(id, target_id)
        data = source.as(Draggable).get_drag_data || return false
        @app.drag_manager.drop_refusal(target, source, data).nil?
      end

      # Focus the widget, then type `text` into it as SFML delivers typing. It PUTS the keyboard there - for a spec
      # about the widget; a spec about where the app leaves the keyboard clicks, then types with `type(text)`.
      def type(id : String, text : String) : Nil
        widget = focusable(id, "type")
        act(widget) do
          Widget.focus_manager.focus(widget)
          @renderer.deliver(@app, Keys.typed(text))
        end
      end

      # Type `text` to whatever holds the keyboard - where the app put it (a click, a dialog opening), never the
      # Driver. Raises when nothing holds it: typing into nothing would pass over what a spec meant to check.
      def type(text : String) : Nil
        raise ArgumentError.new("nothing holds the keyboard - click where the text should go first") unless Widget.focus_manager.focused_widget
        reported { @renderer.deliver(@app, Keys.typed(text)) }
      end

      # A key or chord - "Enter", "Escape", "Ctrl+S", "Ctrl+Shift+Z" - with SFML's key names
      # (SF::Keyboard::Key). `on:` PUTS the keyboard on that widget first; without it the keys go to whatever holds it.
      def press(chord : String, on id : String? = nil) : Nil
        events = chord_events(chord)
        if id
          widget = focusable(id, "press")
          act(widget) do
            Widget.focus_manager.focus(widget)
            @renderer.deliver(@app, events)
          end
        else
          reported { @renderer.deliver(@app, events) }
        end
      end

      # Raw keyboard events (build them with Testing::Keys) - when `type` and `press` cannot say it.
      def keys(events : Array(LibCSFML::Event)) : Nil
        reported { @renderer.deliver(@app, events) }
      end

      # A user action the app REFUSES by raising - real input hands the exception to the app's
      # on_event_exception (SFMLRenderer#handle_event; embrace shows it in the status bar). Inside this
      # block the Driver does the same, and every exception must match `message` - at least one must
      # arrive. Outside it, an act's exception stays loud: a spec never passes over a failed assert.
      def expect_reported(message : Regex | String, &) : Nil
        @app.on_event_exception || raise ArgumentError.new("the app has no on_event_exception to report to")
        raise ArgumentError.new("expect_reported does not nest") if @reports
        reports = @reports = [] of String
        begin
          yield
        ensure
          @reports = nil
        end
        raise ArgumentError.new("expected a report matching #{message.inspect}; the act raised nothing") if reports.empty?
        stray = reports.reject { |r| message.is_a?(Regex) ? r.matches?(message) : r.includes?(message) }
        raise ArgumentError.new("reported, but not #{message.inspect}: #{stray.join("; ")}") unless stray.empty?
      end

      # Turn the mouse wheel over the widget's centre: `notches` positive away from the user, with
      # Ctrl (zoom: App#handle_ctrl_wheel) or Shift (horizontal) as the renderer hands them on.
      def wheel(id : String, notches : Float64, ctrl : Bool = false, shift : Bool = false) : Nil
        at = find(id).viewport_bounds.center
        reported do
          if ctrl
            @app.handle_ctrl_wheel(notches, at)
          else
            @app.handle_mouse_wheel(Vec2.new(0.0, notches), at, shift)
          end
        end
        settle
      end

      # Hover the widget through the app's real hover path, at its centre - position-based, so it
      # raises when something else sits on top there.
      def hover(id : String) : Nil
        widget = find(id)
        refuse_matrix(ancestors(widget), "hover", id, "") # the grid takes the hover
        at = widget.viewport_bounds.center
        hit = @app.root.try(&.hit_test(at))
        unless hit && (hit == widget || ancestors(hit).includes?(widget))
          raise ArgumentError.new("\"#{id}\" is covered at its centre by #{describe(hit)}")
        end
        @app.update_hover(at)
        settle
      end

      # Press a panel's title bar for real (press and release through the app's mouse path): the panel comes to
      # the front as a user's press brings it. The point is a spot of the bar clear of the resize bands and both
      # buttons where the press reaches the bar (not a leading widget, not another panel) - the one farthest from this panel's previous press, so two
      # presses never make the double-click that maximizes it. Raises when no spot of the bar is uncovered.
      def press_title(panel_id : String) : Nil
        panel = panel(panel_id)
        y = panel.y + panel.title_bar_height / 2.0
        left = panel.x + WindowPanel::RESIZE_HANDLE_SIZE
        right = panel.maximize_button_rect.x
        spots = (left.ceil.to_i...right.floor.to_i).step(2).map { |x| Vec2.new(x.to_f, y) }.select { |at| uncovered?(panel, at) }
        raise ArgumentError.new("the title bar of \"#{panel_id}\" is covered") if spots.empty?
        last = @title_presses[panel_id]?
        at = last ? spots.max_by { |spot| (spot.x - last).abs } : spots.first
        @title_presses[panel_id] = at.x
        press_at(panel, at)
      end

      # Press a panel's close button for real. Raises when it is covered or the panel cannot be closed.
      def close_panel(panel_id : String) : Nil
        panel = panel(panel_id)
        raise ArgumentError.new("\"#{panel_id}\" has no close button") unless panel.closeable
        at = panel.close_button_rect.center
        raise ArgumentError.new("the close button of \"#{panel_id}\" is covered") unless uncovered?(panel, at)
        press_at(panel, at)
      end

      # Let `seconds` pass for the app's timers, then settle.
      def advance(seconds : Float64) : Nil
        @now = {@now, Time.instant}.max + seconds.seconds
        @renderer.scheduler.run_expired_timers(@now)
        settle
      end

      # === Grids and file browsers (VirtualMatrix) ===

      # Focus the matrix on one cell, bringing it into view - an off-screen cell has no widget until
      # the matrix materializes it. It PUTS the keyboard on the grid - for a spec about the grid; a spec about
      # where a click leaves the keyboard uses click_cell, then type(text).
      def focus_cell(matrix_id : String, row : Int32, col : Int32) : Nil
        cell_widget(matrix_id, row, col)
      end

      # Drag one cell onto another, in the same grid or another one, the way the mouse does: a press
      # on the source cell through the matrix's own handler, then a drop on the target cell. Both are
      # named by their top-left (row, col). Only the source is brought into view - a real drag never
      # moves the target's cursor - so the target must already be on screen. Raises (Refusal) for
      # what real input would not turn into this drag, naming why.
      def drag_cell(matrix_id : String, row : Int32, col : Int32, onto : {String, Int32, Int32}) : Nil
        cell = {row, col}
        target_id, to_row, to_col = onto
        pressed, at = press_point(matrix_id, cell)
        act(pressed, at: at) do
          press(pressed, matrix_id, cell, at, "drag", MouseButton::Left)
          press_and_drop(pressed, matrix_id, cell, at, target_id, {to_row, to_col})
        end
      end

      # Click one cell the way the mouse does: press and release through the grid's own handlers, with
      # frames between, then the click a release over the same grid makes - it reaches the cell's
      # widget, so a checkbox cell toggles. Named by its top-left, brought into view first.
      def click_cell(matrix_id : String, row : Int32, col : Int32) : Nil
        press_and_release(matrix_id, {row, col}, MouseButton::Left)
      end

      # Right-click one cell the way the mouse does: the grid moves its cursor there and hands the press on
      # to the right-click handler at or above it (a host's cell menu), at the press point in window space.
      # No click follows a right release. Named by its top-left, brought into view first.
      def right_click_cell(matrix_id : String, row : Int32, col : Int32) : Nil
        press_and_release(matrix_id, {row, col}, MouseButton::Right)
      end

      # The grid's cursor cell - a read that moves nothing.
      def cursor(matrix_id : String) : {Int32, Int32}
        matrix(matrix_id).cursor_rc
      end

      # What the cell DISPLAYS (not the stored value). Brings it into view, moving the cursor there.
      def cell_text(matrix_id : String, row : Int32, col : Int32) : String
        text_of(cell_widget(matrix_id, row, col))
      end

      # Select (one click) or open (two) a file in a DirBrowser matrix, by name. A path "sub/x.emb"
      # (or File.join("sub", "x.emb"), the platform's separator) opens each directory on the way first.
      def select_file(matrix_id : String, path : String) : Nil
        choose(matrix_id, path, clicks: 1)
      end

      def open_file(matrix_id : String, path : String) : Nil
        choose(matrix_id, path, clicks: 2)
      end

      # === Reads ===

      # Its own text (a Text, a Button's label, a TextInput's value, a StatusBar's text, a ComboBox's
      # selected value), else its Texts' joined with " ".
      def text(id : String) : String
        text_of(find(id))
      end

      def enabled?(id : String) : Bool
        find(id).enabled?
      end

      def checked?(id : String) : Bool
        case widget = find(id)
        when Checkbox then widget.checked || widget.check_state.checked? # what the box shows (to_primitives)
        when MenuItem then widget.checked
        else               raise ArgumentError.new("\"#{id}\" is a #{widget.class.name}, which has no checked state")
        end
      end

      def focused_id : String?
        Widget.focus_manager.focused_widget.try(&.id)
      end

      # === Internals ===

      # The Driver's own refusal inside an act (no handler, a refused drop) - never handed to the app.
      class Refusal < ArgumentError
      end

      # `at`: where the press lands - popups are dismissed by position. In App#handle_mouse_down's order: the
      # popups close, the widget takes the keyboard when a press would give it, the menus close, its panel
      # comes to the front.
      private def act(widget : Widget, at : Vec2 = widget.viewport_bounds.center, &) : Nil
        @app.dismiss_popups(at)
        Widget.focus_manager.focus(widget) if widget.takes_focus_on_click?
        @app.dismiss_menus(widget)
        widget.bring_containing_panel_to_front
        reported { yield }
      ensure
        settle
      end

      # Inside expect_reported, an exception goes where real input sends it - the app's
      # on_event_exception - and is recorded; anywhere else, and for the Driver's own refusals, it raises.
      private def reported(&) : Nil
        yield
      rescue ex
        reports = @reports
        raise ex if reports.nil? || ex.is_a?(Refusal)
        reports << ex.message.to_s
        @app.on_event_exception.not_nil!.call(ex.message.to_s)
      end

      # Where lookups search: the window tree, then its overlays - narrowed by each `within` scope
      # in turn, each resolved inside the one before it.
      private def roots : Array(Widget)
        root = @app.root || raise ArgumentError.new("the app has no root widget")
        @scopes.reduce([root] + (root.as?(Window).try(&.overlays) || [] of Widget)) do |outer, scope|
          next [scope] if scope.is_a?(Widget)
          [outer.compact_map(&.find_by_id(scope)).first? || raise ArgumentError.new("scope \"#{scope}\" is gone")]
        end
      end

      private def find?(id : String) : Widget?
        roots.each do |root|
          if found = root.find_by_id(id)
            return found
          end
        end
        nil
      end

      private def all(&block : Widget -> Bool) : Array(Widget)
        roots.flat_map(&.find_all(&block))
      end

      private def missing(id : String) : String
        stem = id.rpartition('_')[0]
        near = stem.empty? ? [] of String : all { |w| w.id.try(&.starts_with?(stem)) || false }.compact_map(&.id)
        "no widget with id \"#{id}\"" + (near.empty? ? "" : "; ids like it: #{near.first(12).join(", ")}")
      end

      private def ancestors(widget : Widget, self_too : Bool = false) : Array(Widget)
        chain = self_too ? [widget] : [] of Widget
        current = widget.parent
        while current
          chain << current
          current = current.parent
        end
        chain
      end

      # The widgets a right-click walks until one has a handler.
      private def handler_chain(widget : Widget) : Array(Widget)
        chain = [] of Widget
        ancestors(widget, self_too: true).each do |w|
          chain << w
          break if w.on_right_click_handler
        end
        chain
      end

      # The Draggable at or above `id` and the DropTarget at or above `target_id` - refused through
      # a VirtualMatrix, like every act that would have to guess a cell.
      private def drag_ends(id : String, target_id : String) : {Widget, Widget}
        source = at_or_above(find(id), "draggable") { |w| w.is_a?(Draggable) }
        target = at_or_above(find(target_id), "drop target") { |w| w.is_a?(DropTarget) }
        refuse_matrix(ancestors(source, self_too: true), "drag", id, DRAG_CELL_HINT)
        refuse_matrix(ancestors(target, self_too: true), "drag", target_id, DRAG_CELL_HINT)
        {source, target}
      end

      private def at_or_above(widget : Widget, what : String, &match : Widget -> Bool) : Widget
        ancestors(widget, self_too: true).find(&match) ||
          raise ArgumentError.new("no #{what} at or above \"#{widget.id}\"")
      end

      private DRAG_CELL_HINT        = "; drag a cell with drag_cell"
      private RIGHT_CLICK_CELL_HINT = "; right-click a cell with right_click_cell"
      private CLICK_CELL_HINT       = "; click a cell with click_cell"
      private FOCUS_CELL_HINT       = "; focus a cell with focus_cell"

      # A VirtualMatrix picks its cell from the mouse position; guessing one here would act on the
      # wrong cell. `hint` names the cell-level act, where there is one.
      private def refuse_matrix(chain : Array(Widget), act : String, id : String, hint : String) : Nil
        if chain.any?(VirtualMatrix)
          raise ArgumentError.new("#{act} on \"#{id}\" goes through a VirtualMatrix, which acts on the " \
                                  "cell under the mouse#{hint}")
        end
      end

      # A widget inside a grid is never focused: the grid keeps the focus and hands keys to its cursor cell
      # (proxy focus). The grid itself is focusable.
      private def focusable(id : String, act : String) : Widget
        widget = find(id)
        refuse_matrix(ancestors(widget), act, id, FOCUS_CELL_HINT)
        raise ArgumentError.new("\"#{id}\" is not focusable") unless widget.focusable?
        widget
      end

      private def panel(id : String) : WindowPanel
        widget = find(id)
        widget.as?(WindowPanel) || raise ArgumentError.new("\"#{id}\" is a #{widget.class.name}, not a WindowPanel")
      end

      # `at` in the panel's parent space (where its x and y are): does a press there reach the panel - the panel
      # itself (its buttons, a draggable bar) or its chrome (a fixed bar)?
      private def uncovered?(panel : WindowPanel, at : Vec2) : Bool
        hit = @app.root.try(&.hit_test(window_point(panel, at)))
        !hit.nil? && (hit.same?(panel) || (hit.is_a?(WindowPanel::Chrome) && hit.parent.same?(panel)))
      end

      private def window_point(panel : WindowPanel, at : Vec2) : Vec2
        panel.parent.not_nil!.to_window(at)
      end

      private def press_at(panel : WindowPanel, at : Vec2) : Nil
        point = window_point(panel, at)
        reported { @renderer.deliver(@app, Keys.click_at(point.x.round.to_i, point.y.round.to_i)) }
        settle
      end

      private def matrix(id : String) : VirtualMatrix
        widget = find(id)
        widget.as?(VirtualMatrix) || raise ArgumentError.new("\"#{id}\" is a #{widget.class.name}, not a VirtualMatrix")
      end

      # Reveal a cell (focus, cursor, snap) and return its widget - looked up by the REQUESTED cell,
      # never by the cursor, which place_cursor clamps into range.
      private def cell_widget(matrix_id : String, row : Int32, col : Int32) : Widget
        vm = matrix(matrix_id)
        act(vm) do
          Widget.focus_manager.focus(vm)
          vm.set_cursor_from_cell({row, col})
          vm.snap_to_cursor
        end
        vm = matrix(matrix_id)
        vm.active_cells[vm.get_top_left_cell({row, col})]? ||
          raise ArgumentError.new("\"#{matrix_id}\" has no cell at #{row},#{col}")
      end

      # The grid a cell act presses, revealed, and where the press lands: the centre of what of the cell
      # is painted (aim).
      private def press_point(matrix_id : String, cell : {Int32, Int32}) : {VirtualMatrix, Vec2}
        vm = matrix(matrix_id)
        top_left!(vm, matrix_id, cell)
        cell_widget(matrix_id, cell[0], cell[1]) # revealed, and there
        pressed = matrix(matrix_id) # the reveal settled, which may have rebuilt the grid
        at = aim(pressed, cell) || raise Refusal.new("\"#{matrix_id}\" #{cell[0]},#{cell[1]} is not painted anywhere")
        {pressed, at}
      end

      # A press on a cell, frames, and its release - on the grid found again after them, as App re-finds the
      # pressed widget after a rebuild. A left release over the same grid then clicks, as App's does.
      # `double_click_ok`: the caller knows the press does the same whether the grid counts it as a
      # double-click or not.
      private def press_and_release(matrix_id : String, cell : {Int32, Int32}, button : MouseButton,
                                    double_click_ok : Bool = false) : Nil
        pressed, at = press_point(matrix_id, cell)
        act(pressed, at: at) do
          press(pressed, matrix_id, cell, at, "click", button, double_click_ok)
          released = pressed
          begin
            settle
            released = matrix(matrix_id)
          ensure
            release(released, at, button) # even when a frame raised: never left pressed
          end
          released.trigger_click if button.left? && @app.root.try(&.hit_test(at)).same?(released)
        end
      end

      # The press itself, inside the act: the grid under the point, never the second LEFT press of a
      # double-click (`verb` names the act for the refusal; a right press never is one).
      private def press(pressed : VirtualMatrix, matrix_id : String, cell : {Int32, Int32}, at : Vec2, verb : String,
                        button : MouseButton, double_click_ok : Bool = false) : Nil
        seen!(pressed, matrix_id, cell, at)
        if button.left? && !double_click_ok && pressed.double_click?(cell)
          raise Refusal.new("\"#{matrix_id}\" #{cell[0]},#{cell[1]} was pressed a moment ago, so a press now is a " \
                            "double-click; the grid times clicks with the real clock, which advance cannot " \
                            "move - #{verb} another cell")
        end
        @app.drag_manager.begin_drag_tracking(pressed, at) # as App's press does, before the widget hears it
        begin
          pressed.on_mouse_down(pressed.to_content(at), button)
        rescue ex
          @app.drag_manager.cancel_drag # a press that raised tracks nothing: the next act must not inherit it
          raise ex
        end
      end

      # The release of a press that did not become a drop, as App's: the pending drag it began is cancelled,
      # then the grid hears the release.
      private def release(released : VirtualMatrix, at : Vec2, button : MouseButton) : Nil
        @app.drag_manager.cancel_drag
        released.on_mouse_up(released.to_content(at), button)
      end

      # After the press - unless something refuses - the drop. A press that did not become a drag is
      # released as App releases it (its pending drag cancelled, then on_mouse_up) - never a click, so a
      # refused act triggers no cell - and no refusal leaves a half-pressed grid or a pending drag.
      private def press_and_drop(pressed : VirtualMatrix, matrix_id : String, cell : {Int32, Int32}, at : Vec2,
                                 target_id : String, to : {Int32, Int32}) : Nil
        released = pressed
        dragging = false
        begin
          # Frames run before the mouse crosses the drag threshold. A rebuild among them hands the tracked
          # drag to the instance reconcile paired with the pressed one (App#rebuild -> DragManager#rebind),
          # with the payload the pressed one offered; the re-find by id finds that instance, and the mouse-up
          # would reach it.
          settle
          source = matrix(matrix_id)
          released = source
          carried!(matrix_id, cell)
          target = matrix(target_id)
          drop_at = drop_point(source, target, target_id, to)
          if drop_at.distance_to(at) < DragState::DRAG_THRESHOLD
            raise Refusal.new("\"#{target_id}\" #{to[0]},#{to[1]} is where the drag starts: a press and release " \
                              "that close is a click, which this act cannot express as a drag")
          end
          dragging = true
          if reason = @app.drag_manager.drag_onto(source, target, drop_at)
            raise Refusal.new("dragging \"#{matrix_id}\" #{cell[0]},#{cell[1]} onto \"#{target_id}\" " \
                              "#{to[0]},#{to[1]} was refused: #{reason}")
          end
        ensure
          # Once a drag started, end_drag has cleared the source and real input sends no mouse-up; a
          # drag_onto that raised before starting it leaves the tracked press pending - end that.
          if dragging
            @app.drag_manager.cancel_drag if @app.drag_manager.state.pending?
          else
            release(released, at, MouseButton::Left)
          end
        end
      end

      # Where the drop lands: the centre of what of the target cell is painted (aim), in WINDOW space -
      # the point the mouse is at, which DragManager hands the target in the
      # target's own space. The drag must reach the target there, as a moving drag finds it, and the grid
      # must put the cell there.
      private def drop_point(source : VirtualMatrix, target : VirtualMatrix, target_id : String, to : {Int32, Int32}) : Vec2
        top_left!(target, target_id, to)
        at = aim(target, to)
        unless at && target.viewport_bounds.contains_point(at)
          raise Refusal.new("\"#{target_id}\" #{to[0]},#{to[1]} is not on screen; a drag cannot scroll " \
                            "the target, so bring it into view first")
        end
        # A target that refuses the payload, where the drag reaches nothing else, is real input's refused
        # drop: the drag starts, ends undropped, and drag_onto says why. Anything else there covers the
        # cell - another drop target would take the drop instead.
        data = @app.drag_manager.payload.not_nil! # carried! checked it
        reached = @app.drag_manager.drop_target_at(@app.root.not_nil!, at, source, data)
        unless reached.same?(target) || (reached.nil? && @app.drag_manager.drop_refusal(target, source, data))
          raise Refusal.new("\"#{target_id}\" #{to[0]},#{to[1]} is covered: a drop at its centre reaches " \
                            "#{describe(reached)}")
        end
        landed = target.point_to_cell(target.to_content(at)) # the target's own space, as DragManager hands it
        unless landed == to
          raise Refusal.new("\"#{target_id}\" #{to[0]},#{to[1]} lies under #{landed ? "cell #{landed[0]},#{landed[1]}" : "no cell"} " \
                            "at its centre - a drop there lands on that")
        end
        at
      end

      # The press lands where the mouse would: the source cell on screen, the grid itself under it.
      private def seen!(vm : VirtualMatrix, matrix_id : String, cell : {Int32, Int32}, at : Vec2) : Nil
        hit = @app.root.try(&.hit_test(at))
        raise Refusal.new("\"#{matrix_id}\" #{cell[0]},#{cell[1]} is covered at its centre by #{describe(hit)}") unless hit.same?(vm)
        landed = vm.point_to_cell(vm.to_content(at)).try { |c| vm.get_top_left_cell(c) } # a merge is one cell
        unless landed == cell
          raise Refusal.new("\"#{matrix_id}\" #{cell[0]},#{cell[1]} lies under #{landed ? "cell #{landed[0]},#{landed[1]}" : "no cell"} at its centre")
        end
      end

      # The tracked drag must be about to carry exactly this cell.
      private def carried!(matrix_id : String, cell : {Int32, Int32}) : Nil
        data = @app.drag_manager.payload
        return if data.is_a?(CellDragData) && {data.row, data.col} == cell
        what = data.is_a?(CellDragData) ? "would drag #{data.row},#{data.col} instead" : "has no content to drag"
        raise Refusal.new("\"#{matrix_id}\" #{cell[0]},#{cell[1]} #{what}")
      end

      # A cell is named by its top-left: a merge is one cell to the user.
      private def top_left!(vm : VirtualMatrix, matrix_id : String, cell : {Int32, Int32}) : Nil
        top_left = vm.get_top_left_cell(cell)
        return if top_left == cell
        raise ArgumentError.new("\"#{matrix_id}\" #{cell[0]},#{cell[1]} lies inside the merged cell at " \
                                "#{top_left[0]},#{top_left[1]}; name that")
      end

      # Where a press on the cell lands, in window space: the centre of what of its OWN line pair is painted -
      # the cell's lines (painted_col / painted_row) cut by where its box is painted (VirtualMatrix#painted_rect:
      # its visible part, a header where it is placed). For a merged cell that is its top-left part, which is
      # what a grid drags a merge by - or, when that part lies under a band while the span is pinned beside it,
      # the painted span itself. nil when nothing of it is painted.
      private def aim(vm : VirtualMatrix, cell : {Int32, Int32}) : Vec2?
        box = vm.painted_rect(vm.get_bounding_box(cell), pitch: false) || return nil
        x, w = vm.painted_col(cell[1])
        y, h = vm.painted_row(cell[0])
        at = Rect.new(x, y, w, h).intersection(box) || box
        vm.viewport_bounds.position + at.center
      end

      private def choose(matrix_id : String, path : String, clicks : Int32) : Nil
        # Path#parts, not split('/'): a host builds the path with File.join, which separates with \ on Windows
        # (and on POSIX a \ is part of a name, which Path keeps).
        *dirs, file = Path[path].parts
        dirs.each { |dir| activate_row(matrix_id, dir, 2) }
        activate_row(matrix_id, file, clicks)
      end

      # Click a DirBrowser row `times` times as the mouse does, re-finding it before each click (the host
      # rebuilds). The browser acts on a second click whenever it comes, so one the grid counts as a
      # double-click does the same (its row cell answers no activation).
      private def activate_row(matrix_id : String, name : String, times : Int32) : Nil
        times.times do
          vm = matrix(matrix_id)
          adapter = vm.adapter.as?(Widgets::DirBrowser::MatrixAdapter) ||
                    raise ArgumentError.new("\"#{matrix_id}\" is not a file browser")
          # A directory is listed with a trailing slash ("sub/").
          index = adapter.items.index { |item| item[0] == name || item[0] == "#{name}/" } ||
                  raise ArgumentError.new("no \"#{name}\" in \"#{matrix_id}\"")
          press_and_release(matrix_id, {index + 1, 0}, MouseButton::Left, double_click_ok: true) # row 0 is the header
        end
      end

      private def text_of(widget : Widget) : String
        case widget
        when Text      then widget.text
        when Button    then widget.text
        when Checkbox  then widget.text
        when TextInput then widget.value
        when StatusBar then widget.text
        when ComboBox  then widget.selected_value || "" # the value it shows, without its "»"
        else
          widget.find_all(&.is_a?(Text)).map(&.as(Text).text).join(" ")
        end
      end

      MODIFIERS = {"ctrl" => SF::Keyboard::Key::LControl, "shift" => SF::Keyboard::Key::LShift,
                   "alt" => SF::Keyboard::Key::LAlt}

      private def chord_events(chord : String) : Array(LibCSFML::Event)
        *mods, name = chord.split('+')
        mods = mods.map(&.downcase)
        held = mods.map do |m|
          MODIFIERS[m]? || raise ArgumentError.new("unknown modifier \"#{m}\" in \"#{chord}\" (Ctrl, Shift, Alt)")
        end
        key = SF::Keyboard::Key.parse?(name) ||
              raise ArgumentError.new("unknown key \"#{name}\" in \"#{chord}\" - SFML's names (Enter, Escape, " \
                                      "Tab, Delete, PageDown, A-Z, Num0-Num9, F1-F15; see docs/TESTING.md)")
        flags = {control: mods.includes?("ctrl"), shift: mods.includes?("shift"), alt: mods.includes?("alt")}
        held.map { |m| Keys.pressed(m, **flags) } +
          [Keys.pressed(key, **flags), Keys.released(key, **flags)] +
          held.reverse.map { |m| Keys.released(m, **flags) }
      end

      private def describe(widget : Widget?) : String
        return "nothing" unless widget
        widget.id ? "\"#{widget.id}\"" : "a #{widget.class.name}"
      end
    end
  end
end
