module CrymbleUI
  # Cache policy for widget primitive generation
  #
  # Determines when primitives should be cached vs. regenerated
  enum CachePolicy
    # Never cache primitives - always regenerate
    # Use for: Menus, popups, animations, frequently changing content
    Never

    # Cache primitives, invalidate on state change
    # Use for: Buttons, text, most interactive widgets
    # This is the default for most widgets
    Dynamic

    # Cache primitives aggressively, rarely invalidate
    # Use for: Window chrome, static content that never changes
    # Can also enable texture caching at renderer level
    Static
  end
end
