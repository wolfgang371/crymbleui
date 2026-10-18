require "spec"

# Proves the runner can fail: exactly one failure and one error are expected, and spec.sh requires both.
GC.disable

describe "a planted failure" do
  it "fails an assertion" { (1 + 1).should eq 3 }
  it "errors on an unexpected raise" { raise "planted" }
  it "passes" { 1.should eq 1 }
end
