require "../spec_helper"
require "../../src/testing/driver"
require "../../tutorials/tutorial-29"

describe TodoApp do
  it "adds items and counts the open ones" do
    ui = CrymbleUI::Testing::Driver.new(TodoApp.new)

    ui.type "new_title", "Milk"
    ui.click "add"
    ui.type "new_title", "Bread"
    ui.click "add"

    ui.text("done_1").should eq("Milk")
    ui.text("done_2").should eq("Bread")
    ui.text("new_title").should eq("")
    ui.text("open_count").should eq("2 open")

    ui.click "done_1"
    ui.checked?("done_1").should be_true
    ui.text("open_count").should eq("1 open")
  end

  it "keeps an item's ids when an item above it goes" do
    ui = CrymbleUI::Testing::Driver.new(TodoApp.new)
    ui.type "new_title", "Milk"
    ui.click "add"
    ui.type "new_title", "Bread"
    ui.click "add"
    ui.click "done_2"

    ui.click "remove_1"

    ui.present?("done_1").should be_false
    ui.text("done_2").should eq("Bread")
    ui.checked?("done_2").should be_true
    ui.text("open_count").should eq("0 open")
  end
end
