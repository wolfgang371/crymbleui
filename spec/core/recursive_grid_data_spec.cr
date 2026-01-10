require "../spec_helper"
require "../../src/core/recursive_grid_data"

# Alias for convenience (must be outside describe block)
alias TestGrid = CrymbleUI::RecursiveGridData::Grid

describe CrymbleUI::RecursiveGridData do
  it "simple row" do
    grid = TestGrid(Int32).new([[10, 20]])
    grid.size.should eq({1, 2})
    grid.get_matrix.should eq([[10, 20]])
  end

  it "simple column" do
    grid = TestGrid(Int32).new([[10], [20]])
    grid.size.should eq({2, 1})
    grid.get_matrix.should eq([[10], [20]])
  end

  it "simple 2x2 matrix" do
    grid = TestGrid(Int32).new([[10, 20], [30, 40]])
    grid.size.should eq({2, 2})
    grid.get_matrix.should eq([
      [10, 20],
      [30, 40],
    ])
  end

  it "simple recursion doesn't change result" do
    grid = TestGrid(Int32).new([[TestGrid(Int32).new([[10, 20], [30, 40]])]])
    grid.size.should eq({2, 2})
    grid.get_matrix.should eq([
      [10, 20],
      [30, 40],
    ])
  end

  it "checking #elements in simple use case" do
    grid = TestGrid(Int32).new([[10, 20], [30, 40]])
    arr = Array(Tuple(Int32, Tuple(Int32, Int32), Tuple(Int32, Int32))).new
    grid.elements { |el| arr << {el[0], el[1], el[2]} }
    arr.should eq([
      {10, {0, 0}, {0, 0}},
      {20, {0, 1}, {0, 1}},
      {30, {1, 0}, {1, 0}},
      {40, {1, 1}, {1, 1}},
    ])
  end

  it "simple nesting and spanning, variant 1" do
    grid = TestGrid(Int32).new([[10, TestGrid(Int32).new([[20], [30]])]])
    grid.size.should eq({2, 2})
    grid.get_matrix.should eq([
      [10, 20],
      [10, 30],
    ])
  end

  it "three levels" do
    grid = TestGrid(Int32).new([[10, TestGrid(Int32).new([[20, TestGrid(Int32).new([[30]])]])]])
    grid.size.should eq({1, 3})
    grid.get_matrix.should eq([
      [10, 20, 30],
    ])
  end

  it "simple nesting and spanning, variant 2" do
    grid = TestGrid(Int32).new([[TestGrid(Int32).new([[10]]), TestGrid(Int32).new([[20], [30]])]])
    grid.size.should eq({2, 2})
    grid.get_matrix.should eq([
      [10, 20],
      [10, 30],
    ])
  end

  it "disable spanning with empty grid" do
    # Empty grid stops spanning - cells above it become nil
    grid = TestGrid(Int32).new([[TestGrid(Int32).new([[10], [TestGrid(Int32).new]]), TestGrid(Int32).new([[20], [30], [40]])]])
    grid.size.should eq({3, 2})
    grid.get_matrix.should eq([
      [10, 20],
      [nil, 30],
      [nil, 40],
    ])
  end

  it "unbalanced spanning" do
    grid = TestGrid(Int32).new([[TestGrid(Int32).new([[10], [20], [30]]), TestGrid(Int32).new([[40]]), TestGrid(Int32).new([[50], [60]])]])
    grid.size.should eq({3, 3})
    grid.get_matrix.should eq([
      [10, 40, 50],
      [20, 40, 60],
      [30, 40, 60],
    ])
  end

  it "spanning in two dimensions" do
    grid = TestGrid(Int32).new([
      [TestGrid(Int32).new([[10]]), TestGrid(Int32).new([[20], [30]])],
      [TestGrid(Int32).new([[40, 50]]), TestGrid(Int32).new],
    ])
    grid.size.should eq({3, 3})
    grid.get_matrix.should eq([
      [10, 10, 20],
      [10, 10, 30],
      [40, 50, nil],
    ])
  end

  it "late changes with replace" do
    subgrid = TestGrid(Int32).new([[20], [30]])
    grid = TestGrid(Int32).new([[10, subgrid]])
    grid.size.should eq({2, 2})
    grid.get_matrix.should eq([
      [10, 20],
      [10, 30],
    ])

    grid.replace { |m| m[0][0] = 90; m }
    grid.get_matrix.should eq([
      [90, 20],
      [90, 30],
    ])

    subgrid.replace { |_m| [[20, 30], [40, 50]] }
    grid.get_matrix.should eq([
      [90, 20, 30],
      [90, 40, 50],
    ])
  end

  it "grids iterator returns nesting levels and bounds" do
    grid = TestGrid(Int32).new([[10, TestGrid(Int32).new([[20], [30]])]])
    arr = Array(Tuple(Int32, Tuple(Int32, Int32), Tuple(Int32, Int32))).new
    grid.grids { |level, _g, bmin, bmax| arr << {level, bmin, bmax} }
    arr.should eq([
      {0, {0, 0}, {1, 1}},
      {1, {0, 1}, {1, 1}},
    ])
  end

  it "handles edge case with spanning" do
    grid = TestGrid(Int32).new([[10, 20], [30, TestGrid(Int32).new([[40, 50]])]])
    grid.get_matrix.should eq([
      [10, 20, 20],
      [30, 40, 50],
    ])
  end
end
