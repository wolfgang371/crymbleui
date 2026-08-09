require "../spec_helper"
require "../../src/widgets/text_input"

# Paste sanitisation policy for a single-line TextInput.
#
# A single-line input now receives payloads it never saw before (a spreadsheet row
# is tab- and newline-laden by construction). The policy, in order:
#   1. collapse the `\r\n` PAIR to `\n`         (so a Windows break yields ONE space)
#   2. trim leading/trailing line breaks        (a copied cell arrives with a
#      trailing terminator; it is not content — and spaces the user copied are
#      deliberately NOT trimmed)
#   3. map `\n`, `\r` and `\t` to a single space (content is KEPT — tab is the TSV
#      field separator, so dropping it would silently weld fields)
#   4. remove what remains of what the typing path refuses (`< 32`, and 127) — the
#      same character filter the renderer applies to typed input
#   5. guard on the SANITISED-empty result, BEFORE delete_selection
#
# Step 4 cannot come first: `\r` and `\n` are themselves C0, so removing before
# mapping would weld two lines into an unreadable run-on.
#
# Control characters are CONSTRUCTED (`1.chr`), never written as literal bytes: a
# literal control char in source is invisible to review and is silently dropped or
# mangled by editing tools — which already cost this file one round of false GREENs.
describe CrymbleUI::TextInput do
    describe "paste sanitisation" do
        ctl = 1.chr   # a C0 control character the typing path refuses
        del = 127.chr # DEL: not C0, but also refused by the typing path

        # --- These carry the change (RED against the previous verbatim insert) ------

        it "turns a CRLF line break into a single space" do
            CrymbleUI::Widget.clipboard.text = "l1\r\nl2"
            input = CrymbleUI::TextInput.new(value: "")
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("l1 l2")
        end

        it "turns a lone CR into a single space (never welds the lines together)" do
            CrymbleUI::Widget.clipboard.text = "a\rb"
            input = CrymbleUI::TextInput.new(value: "")
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("a b")
        end

        it "turns a TAB into a space so TSV fields stay separated" do
            CrymbleUI::Widget.clipboard.text = "name\t30\tBerlin"
            input = CrymbleUI::TextInput.new(value: "")
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("name 30 Berlin")
        end

        it "trims the trailing line break a copied cell arrives with" do
            # Copying ONE cell from a spreadsheet yields "value\r\n". The break is a
            # terminator, not content — pasting it as "value " would commit a
            # trailing space into the field.
            CrymbleUI::Widget.clipboard.text = "value\r\n"
            input = CrymbleUI::TextInput.new(value: "")
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("value")
        end

        it "leaves the selection INTACT when the payload is only a line break" do
            # Copying an EMPTY cell yields "\r\n". Flattened without the trim that is
            # " " — non-empty, so it would replace the selection with a space.
            CrymbleUI::Widget.clipboard.text = "\r\n"
            input = CrymbleUI::TextInput.new(value: "hello")
            input.on_key_down(SF::Keyboard::Key::A, true, false)
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("hello")
            input.has_selection?.should be_true
        end

        it "advances the caret by the SANITISED length, not the raw one" do
            # "l1\r\nl2" is 6 chars raw and 5 sanitised. Advancing by the raw length
            # is the off-by-N a sanitisation refactor leaves behind.
            CrymbleUI::Widget.clipboard.text = "l1\r\nl2"
            input = CrymbleUI::TextInput.new(value: "")
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("l1 l2")
            input.cursor_pos.should eq(5)
        end

        it "strips a C0 control character the typing path would refuse" do
            CrymbleUI::Widget.clipboard.text = "a#{ctl}b"
            input = CrymbleUI::TextInput.new(value: "")
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("ab")
        end

        it "strips DEL, which is not C0 but is refused by the typing path" do
            CrymbleUI::Widget.clipboard.text = "a#{del}b"
            input = CrymbleUI::TextInput.new(value: "")
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("ab")
        end

        it "leaves the selection INTACT when a non-empty payload sanitises to empty" do
            # The previous guard tested the RAW payload, so "#{ctl}" passed it,
            # deleted the selection and inserted a control char — data destroyed by
            # a paste that should have been a no-op.
            CrymbleUI::Widget.clipboard.text = "#{ctl}"
            input = CrymbleUI::TextInput.new(value: "hello")
            input.on_key_down(SF::Keyboard::Key::A, true, false) # select all
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("hello")
        end

        # A grid-style copy that puts TSV on the clipboard is pasted here as text, with
        # no provenance check: the library deliberately carries no "who wrote this"
        # tag, so a user who copies structured data and then pastes it into a text
        # field gets that text. Their own doing, not something the widget prevents.
        it "pastes a TSV payload as flattened text, no questions asked" do
            CrymbleUI::Widget.clipboard.text = "a\tb\tc"
            input = CrymbleUI::TextInput.new(value: "")
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("a b c")
        end

        # --- New capability: inexpressible against the old String-returning API -----

        it "leaves the selection intact when NOTHING has been copied (text is nil)" do
            # A fresh clipboard has never been written to: ABSENT, not empty. The old
            # accessor returned "" for both, so this state could not be written down.
            # Only TestClipboard can produce it today — see SFMLClipboard's note.
            CrymbleUI::Widget.clipboard.text.should be_nil
            input = CrymbleUI::TextInput.new(value: "hello")
            input.on_key_down(SF::Keyboard::Key::A, true, false)
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("hello")
        end

        # --- Regression guards: GREEN ON ARRIVAL ------------------------------------
        # These pass before the change too. They pin behaviour the sanitisation
        # refactor could plausibly break; they do NOT witness the fix.

        it "(green on arrival) counts the caret in characters, not bytes" do
            # Non-ASCII now round-trips through the production backend too (the
            # wrapper uses SFML's UTF-32 entry points), so this payload is no longer
            # instrument-only. It pins char-vs-byte caret arithmetic, which the ASCII
            # cases cannot reach: "Müller" is 6 characters and 7 bytes.
            CrymbleUI::Widget.clipboard.text = "Müller"
            input = CrymbleUI::TextInput.new(value: "")
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("Müller")
            input.cursor_pos.should eq(6) # 6 chars, 7 bytes
        end

        it "(green on arrival) leaves the selection intact on an empty clipboard" do
            CrymbleUI::Widget.clipboard.text = ""
            input = CrymbleUI::TextInput.new(value: "hello")
            input.on_key_down(SF::Keyboard::Key::A, true, false)
            input.on_key_down(SF::Keyboard::Key::V, true, false)

            input.value.should eq("hello")
        end
    end
end
