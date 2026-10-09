# Tutorial 29: Testing it headless
# ================================
# A small to-do app and its use-case spec, which runs headless: no window, no pixels, no
# coordinates. The spec acts on widgets by id through the test Driver and reads what the user
# would see.
#
# Key concepts:
# - Give every widget a user acts on an id: CrymbleUI::Testing::Driver clicks, types and reads by it.
# - Derive an id from what the thing IS (here the item's number), never from its position or its
#   label: the spec's handles then survive removing the item above, or a rename.
# - The spec is spec/tutorials/tutorial_29_spec.cr; docs/TESTING.md has the Driver's reference.
#
# Run with: shards build tutorial-29 && ./bin/tutorial-29
# Test with: crystal spec spec/tutorials/tutorial_29_spec.cr

require "../src/crymble-ui"

class TodoApp < CrymbleUI::App
  record Item, number : Int32, title : String, done : Bool = false

  state items : Array(Item) = [] of Item
  state draft : String = ""
  @next_number = 1

  def build : CrymbleUI::Widget
    window("Tutorial 29: Testing it headless", 420, 320) do
      vstack(spacing: 8.0, padding: 16.0) do
        hstack(spacing: 8.0) do
          text_input(value: draft, placeholder: "What needs doing?", width: 260.0, id: "new_title") do |value|
            self.draft = value
          end
          button("Add", id: "add") { add }
        end

        items.each do |item|
          hstack(spacing: 8.0) do
            checkbox(item.title, checked: item.done, id: "done_#{item.number}") { toggle(item) }
            button("Remove", id: "remove_#{item.number}") { remove(item) }
          end
        end

        text("#{items.count { |item| !item.done }} open", id: "open_count")
      end
    end
  end

  private def add : Nil
    return if draft.blank?
    self.items = items + [Item.new(@next_number, draft.strip)]
    @next_number += 1
    self.draft = ""
  end

  private def toggle(item : Item) : Nil
    self.items = items.map { |i| i.number == item.number ? i.copy_with(done: !i.done) : i }
  end

  private def remove(item : Item) : Nil
    self.items = items.reject { |i| i.number == item.number }
  end
end

# The spec requires this file and drives the app headless, so it must not open a window.
{% unless @top_level.has_constant?("Spec") %}
  CrymbleUI.run(TodoApp.new)
{% end %}
