# Cross-process witness that non-ASCII survives the clipboard in BOTH directions.
#
# WHY THIS CANNOT BE A SPEC: `Testing::TestClipboard` stores a Crystal String
# verbatim, so it round-trips non-ASCII whether or not the real path does — it cannot
# fail on this bug. The only honest witness is real bytes crossing a PROCESS boundary
# through the OS clipboard, which needs a display and a second process.
#
# Build (needs `source setup.sh` for the CSFML library path):
#   crystal build --release -o /tmp/clipboard-probe tools/clipboard-roundtrip-probe.cr
#
# WRITE direction — we publish, a foreign process reads:
#   /tmp/clipboard-probe serve &
#   xclip -o -selection clipboard | cmp - <reference-utf8-file>
#
# READ direction — a foreign process publishes, we read:
#   xclip -i -selection clipboard <reference-utf8-file>
#   /tmp/clipboard-probe read          # prints PASS/FAIL against PAYLOAD
#
# `serve` opens a window and PUMPS EVENTS, and that is not incidental: SFML answers
# SelectionRequest only from its window event loop, so a windowless process takes X
# selection ownership and then never answers — a foreign reader waits and gets
# nothing. (Same mechanism as the self-paste deadlock the X11 work must solve.)
#
# BLIND SPOTS: says nothing about payloads large enough to trigger INCR (SFML refuses
# INCR on read and sends flat on write), nothing about Wayland, and nothing about
# which X11 target atom a real application negotiates — it only compares bytes.
require "../src/csfml3/wrapper"

PAYLOAD = "Müller\tGrüße\tZürich\tÄÖÜ\tstraße\t€\tnaïve"

def report(got : String)
  puts "READ   #{got.inspect} (#{got.size} chars, #{got.bytesize} bytes)"
  if got == PAYLOAD
    puts "PASS   byte-identical round trip"
  else
    puts "FAIL   expected #{PAYLOAD.inspect}"
    limit = Math.min(PAYLOAD.size, got.size)
    at = (0...limit).find { |i| PAYLOAD[i] != got[i] } || limit
    puts "       first divergence at char #{at}"
  end
end

case ARGV[0]? || "read"
when "serve"
  window = SF::RenderWindow.new(SF::VideoMode.new(200, 80), "clipboard probe")
  SF::Clipboard.string = PAYLOAD
  puts "SERVE  #{PAYLOAD.inspect} (#{PAYLOAD.size} chars, #{PAYLOAD.bytesize} bytes)"
  STDOUT.flush
  loop { window.poll_event }
when "read"
  report(SF::Clipboard.string)
else
  puts "usage: umlaut_probe serve|read"
end
