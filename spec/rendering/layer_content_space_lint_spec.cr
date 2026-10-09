require "spec"
require "../spec_helper"

# The content-space tripwire: a layer owner states its layer's rect in its CONTENT space (absolute_bounds, its
# layout), and the Layer derives the window position (Layer#bounds = content_rect - the owner's enclosing scroll).
# An override that answers in window space (viewport_bounds) renders its content shifted by every ancestor's
# scroll after a repaint - and looks right until something scrolls.
#
# It reads SOURCE TEXT, so it catches the direct spelling only: a helper that returns viewport_bounds is not seen.
# The rule is in docs/LAYER_RENDERING_ARCHITECTURE.md (the coordinate table).
describe "layer content-space tripwire" do
  it "finds no viewport_bounds in any compute_bounds_for_layer" do
    offenders = [] of String
    owners = 0
    src_glob("src/**/*.cr").each do |path|
      lines = File.read_lines(path)
      lines.each_with_index do |line, i|
        next unless line =~ /^(\s*)def compute_bounds_for_layer\b/
        owners += 1
        indent = $1
        j = i + 1
        while j < lines.size && lines[j] != "#{indent}end"
          offenders << "#{path}:#{j + 1}: #{lines[j].strip}" if lines[j].split('#').first.includes?("viewport_bounds")
          j += 1
        end
      end
    end
    (owners >= 8).should be_true # instrument: the scan finds the owners (8 when written)
    offenders.should be_empty, "compute_bounds_for_layer must answer in content space:\n#{offenders.join("\n")}"
  end
end
