require "json"
require "./types"
require "./cached"

module CrymbleUI
  # Immutable theme data parsed from JSON.
  # All color values are pre-parsed Color structs for zero-cost access at runtime.
  struct ThemeData
    getter name : String

    # === COLORS ===

    # Global
    getter app_background : Color
    getter text_default : Color

    # Button
    getter button_text : Color
    getter button_background : Color
    getter button_border : Color

    # TextInput
    getter input_text : Color
    getter input_background : Color
    getter input_border : Color
    getter input_border_focused : Color
    getter input_placeholder : Color
    getter input_selection : Color

    # Checkbox
    getter checkbox_text : Color
    getter checkbox_box : Color
    getter checkbox_check : Color

    # Menu
    getter menu_text : Color
    getter menu_background : Color
    getter menu_hover : Color
    getter menu_border : Color

    # MenuItem
    getter menu_item_text : Color
    getter menu_item_shortcut : Color
    getter menu_item_hover : Color

    # MenuBar
    getter menubar_background : Color
    getter menubar_border : Color

    # WindowPanel
    getter panel_title_bar : Color
    getter panel_title_bar_active : Color
    getter panel_title_bar_inactive : Color
    getter panel_title_text : Color
    getter panel_border : Color
    getter panel_background : Color

    # Popup
    getter popup_background : Color
    getter popup_border : Color

    # StatusBar
    getter statusbar_text : Color
    getter statusbar_background : Color
    getter statusbar_border : Color

    # Scrollbar
    getter scrollbar_track : Color
    getter scrollbar_thumb : Color
    getter scrollbar_arrow : Color

    # ComboBox
    getter combo_text : Color
    getter combo_background : Color
    getter combo_border : Color
    getter combo_hover : Color
    getter combo_selected : Color

    # Separator
    getter separator_color : Color

    # Grid / VirtualMatrix
    getter grid_content_background : Color
    getter grid_cursor_band : Color
    getter grid_cursor_flash : Color

    # Ruler
    getter ruler_background : Color
    getter ruler_label : Color
    getter ruler_line : Color

    # Drag & Drop
    getter drag_highlight : Color
    getter drag_ghost : Color
    getter dropzone_hover : Color
    getter dropzone_background : Color

    # === BRIGHTNESS CONSTANTS ===
    getter brightness_hover : Float64
    getter brightness_focus : Float64
    getter brightness_drag_opacity : Float64
    getter brightness_cursor_delta : Int32

    def initialize(
      @name : String,
      @app_background : Color,
      @text_default : Color,
      @button_text : Color,
      @button_background : Color,
      @button_border : Color,
      @input_text : Color,
      @input_background : Color,
      @input_border : Color,
      @input_border_focused : Color,
      @input_placeholder : Color,
      @input_selection : Color,
      @checkbox_text : Color,
      @checkbox_box : Color,
      @checkbox_check : Color,
      @menu_text : Color,
      @menu_background : Color,
      @menu_hover : Color,
      @menu_border : Color,
      @menu_item_text : Color,
      @menu_item_shortcut : Color,
      @menu_item_hover : Color,
      @menubar_background : Color,
      @menubar_border : Color,
      @panel_title_bar : Color,
      @panel_title_bar_active : Color,
      @panel_title_bar_inactive : Color,
      @panel_title_text : Color,
      @panel_border : Color,
      @panel_background : Color,
      @popup_background : Color,
      @popup_border : Color,
      @statusbar_text : Color,
      @statusbar_background : Color,
      @statusbar_border : Color,
      @scrollbar_track : Color,
      @scrollbar_thumb : Color,
      @scrollbar_arrow : Color,
      @combo_text : Color,
      @combo_background : Color,
      @combo_border : Color,
      @combo_hover : Color,
      @combo_selected : Color,
      @separator_color : Color,
      @grid_content_background : Color,
      @grid_cursor_band : Color,
      @grid_cursor_flash : Color,
      @ruler_background : Color,
      @ruler_label : Color,
      @ruler_line : Color,
      @drag_highlight : Color,
      @drag_ghost : Color,
      @dropzone_hover : Color,
      @dropzone_background : Color,
      @brightness_hover : Float64,
      @brightness_focus : Float64,
      @brightness_drag_opacity : Float64,
      @brightness_cursor_delta : Int32,
      @all_colors : Hash(String, Color) = {} of String => Color,
    )
    end

    # Generic color access for app-specific theme extensions.
    # An app OWNS its color tokens and registers them via
    # Theme.register_colors(variant, {...}); it does NOT put them in the lib's
    # theme JSON (which stays generic). Access via Theme.current["app.token"].
    def [](key : String) : Color
      @all_colors[key]
    end

    def []?(key : String) : Color?
      @all_colors[key]?
    end

    # Merge app-registered tokens into this theme's color table. @all_colors is a
    # shared Hash reference (a struct copy shares it, not its contents), so this
    # updates the live theme in place. Startup-only, via Theme.register_colors —
    # not a runtime mutation path.
    def merge_colors!(colors : Hash(String, Color)) : Nil
      @all_colors.merge!(colors)
    end

    # Parse a ThemeData from a JSON string
    def self.from_json_string(json_str : String) : ThemeData
      data = JSON.parse(json_str)
      colors = data["colors"]
      constants = data["constants"]

      # Parse ALL color keys into generic hash for app-specific extensions
      all_colors = Hash(String, Color).new
      colors.as_h.each do |key, value|
        all_colors[key.to_s] = Color.from_hex(value.as_s)
      end

      ThemeData.new(
        name: data["name"].as_s,
        app_background: Color.from_hex(colors["app.background"].as_s),
        text_default: Color.from_hex(colors["text.default"].as_s),
        button_text: Color.from_hex(colors["button.text"].as_s),
        button_background: Color.from_hex(colors["button.background"].as_s),
        button_border: Color.from_hex(colors["button.border"].as_s),
        input_text: Color.from_hex(colors["input.text"].as_s),
        input_background: Color.from_hex(colors["input.background"].as_s),
        input_border: Color.from_hex(colors["input.border"].as_s),
        input_border_focused: Color.from_hex(colors["input.border_focused"].as_s),
        input_placeholder: Color.from_hex(colors["input.placeholder"].as_s),
        input_selection: Color.from_hex(colors["input.selection"].as_s),
        checkbox_text: Color.from_hex(colors["checkbox.text"].as_s),
        checkbox_box: Color.from_hex(colors["checkbox.box"].as_s),
        checkbox_check: Color.from_hex(colors["checkbox.check"].as_s),
        menu_text: Color.from_hex(colors["menu.text"].as_s),
        menu_background: Color.from_hex(colors["menu.background"].as_s),
        menu_hover: Color.from_hex(colors["menu.hover"].as_s),
        menu_border: Color.from_hex(colors["menu.border"].as_s),
        menu_item_text: Color.from_hex(colors["menu_item.text"].as_s),
        menu_item_shortcut: Color.from_hex(colors["menu_item.shortcut"].as_s),
        menu_item_hover: Color.from_hex(colors["menu_item.hover"].as_s),
        menubar_background: Color.from_hex(colors["menubar.background"].as_s),
        menubar_border: Color.from_hex(colors["menubar.border"].as_s),
        panel_title_bar: Color.from_hex(colors["panel.title_bar"].as_s),
        panel_title_bar_active: Color.from_hex(colors["panel.title_bar_active"].as_s),
        panel_title_bar_inactive: Color.from_hex(colors["panel.title_bar_inactive"].as_s),
        panel_title_text: Color.from_hex(colors["panel.title_text"].as_s),
        panel_border: Color.from_hex(colors["panel.border"].as_s),
        panel_background: Color.from_hex(colors["panel.background"].as_s),
        popup_background: Color.from_hex(colors["popup.background"].as_s),
        popup_border: Color.from_hex(colors["popup.border"].as_s),
        statusbar_text: Color.from_hex(colors["statusbar.text"].as_s),
        statusbar_background: Color.from_hex(colors["statusbar.background"].as_s),
        statusbar_border: Color.from_hex(colors["statusbar.border"].as_s),
        scrollbar_track: Color.from_hex(colors["scrollbar.track"].as_s),
        scrollbar_thumb: Color.from_hex(colors["scrollbar.thumb"].as_s),
        scrollbar_arrow: Color.from_hex(colors["scrollbar.arrow"].as_s),
        combo_text: Color.from_hex(colors["combo.text"].as_s),
        combo_background: Color.from_hex(colors["combo.background"].as_s),
        combo_border: Color.from_hex(colors["combo.border"].as_s),
        combo_hover: Color.from_hex(colors["combo.hover"].as_s),
        combo_selected: Color.from_hex(colors["combo.selected"].as_s),
        separator_color: Color.from_hex(colors["separator.color"].as_s),
        grid_content_background: Color.from_hex(colors["grid.content_background"].as_s),
        grid_cursor_band: Color.from_hex(colors["grid.cursor_band"].as_s),
        grid_cursor_flash: Color.from_hex(colors["grid.cursor_flash"].as_s),
        ruler_background: Color.from_hex(colors["ruler.background"].as_s),
        ruler_label: Color.from_hex(colors["ruler.label"].as_s),
        ruler_line: Color.from_hex(colors["ruler.line"].as_s),
        drag_highlight: Color.from_hex(colors["drag.highlight"].as_s),
        drag_ghost: Color.from_hex(colors["drag.ghost"]?.try(&.as_s) || colors["drag.highlight"].as_s),
        dropzone_hover: Color.from_hex(colors["dropzone.hover"].as_s),
        dropzone_background: Color.from_hex(colors["dropzone.background"].as_s),
        brightness_hover: constants["brightness.hover"].as_f,
        brightness_focus: constants["brightness.focus"].as_f,
        brightness_drag_opacity: constants["brightness.drag_opacity"].as_f,
        brightness_cursor_delta: constants["brightness.cursor_delta"].as_i,
        all_colors: all_colors,
      )
    end
  end

  # A LIVE theme-color reference: wraps a ThemeData accessor and resolves it against
  # Theme.current at READ time. Pass `Theme.ref(&.ruler_label)` where a call site needs a theme color
  # whose key differs from the widget's own default — it follows Theme.set, unlike a snapshotted
  # Theme.current.<key> argument (which becomes a sticky override).
  struct ThemeColorRef
    def initialize(@accessor : ThemeData -> Color)
    end

    def resolve : Color
      @accessor.call(Theme.current)
    end
  end

  # What a theme-aware color property accepts: a concrete Color (sticky override) or a live ThemeColorRef.
  alias ThemeColor = Color | ThemeColorRef

  # Global theme registry and singleton accessor.
  #
  # Usage:
  #   Theme.current.button_background  # => Color (from active theme)
  #   Theme.set(:dark)                 # Switch to dark theme
  #   Theme.register(:custom, data)    # Register custom theme
  #   Theme.ref(&.ruler_label)         # => a live reference resolved at read time
  module Theme
    # Compile-time embedded JSON (zero runtime I/O)
    LIGHT_JSON = {{ read_file("#{__DIR__}/../../resources/themes/light.json") }}
    DARK_JSON  = {{ read_file("#{__DIR__}/../../resources/themes/dark.json") }}

    # Pre-parsed theme data
    @@themes : Hash(Symbol, ThemeData) = {
      :light => ThemeData.from_json_string(LIGHT_JSON),
      :dark  => ThemeData.from_json_string(DARK_JSON),
    }

    # Current active theme (defaults to light), held in a tracked Source so a Cached node that READS
    # Theme.current during its recompute AUTO-CAPTURES the theme edge. Reading it
    # outside a recompute (CacheNode.current == nil) just returns the value — zero behaviour change.
    @@current_source : Source(ThemeData) = Source(ThemeData).new(@@themes[:light])
    @@current_name : Symbol = :light # the active theme's registry name (for a live toggle)

    def self.current : ThemeData
      @@current_source.get
    end

    # Observability: how many pull nodes currently depend on the theme Source. A dependents leak shows
    # as this growing per rebuild; the dispose-on-rebuild fix keeps it at ~one live generation.
    def self.current_source_dependent_count : Int32
      @@current_source.dependent_count
    end

    # The active theme's registry name (e.g. :light / :dark).
    def self.current_name : Symbol
      @@current_name
    end

    # Build a live theme-color reference: `Theme.ref(&.ruler_label)` resolves Theme.current.ruler_label
    # at read time (follows Theme.set), for call sites needing a key other than a widget's own default.
    def self.ref(&accessor : ThemeData -> Color) : ThemeColorRef
      ThemeColorRef.new(accessor)
    end

    def self.set(name : Symbol)
      theme = @@themes[name]?
      raise "Unknown theme: #{name}" unless theme
      @@current_source.set(theme) # bumps the Source version + marks auto-captured dependents dirty
      @@current_name = name
    end

    def self.register(name : Symbol, theme : ThemeData)
      @@themes[name] = theme
    end

    # Register app-owned color tokens for a theme variant. Keeps the lib generic:
    # the app names + values its own tokens (e.g. "constraint.ok") instead of them
    # living in the lib's theme JSON. Call once at startup, before the first read.
    def self.register_colors(variant : Symbol, colors : Hash(String, Color)) : Nil
      theme = @@themes[variant]?
      raise "Unknown theme: #{variant}" unless theme
      theme.merge_colors!(colors)
    end

    def self.available : Array(Symbol)
      @@themes.keys
    end
  end
end
