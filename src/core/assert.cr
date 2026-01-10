# Runtime assertion macro - always enabled (not just in DEBUG mode)
# Provides compile-time and runtime invariant checking with file:line info
# Usage: assert(condition, "error message")
macro assert(invariant, message = nil, f = __FILE__, l = __LINE__)
  {% if invariant %}
    if {{invariant}} # see https://github.com/crystal-lang/crystal/issues/13209
    else
      {% if message %}
        raise("INVARIANT VIOLATION @" + {{f}} + ":{{l}}: " + {{message}})
      {% else %}
        raise("INVARIANT VIOLATION @" + {{f}} + ":{{l}}")
      {% end %}
    end
  {% else %}
    {% if message %}
      raise("INVARIANT VIOLATION @" + {{f}} + ":{{l}}: " + {{message}})
    {% else %}
      raise("INVARIANT VIOLATION @" + {{f}} + ":{{l}}")
    {% end %}
  {% end %}
end
