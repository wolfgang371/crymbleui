# RecursiveGrid data structure for 2D grids with recursive nesting
# Ported from: https://github.com/wolfgang371/recursivegrid
#
# Core concept: A grid where cells can contain elements OR nested grids.
# Nested grids automatically cause sibling cells to span multiple rows/columns.
#
# Example:
#   grid = Grid.new([[10, Grid.new([[20],[30]])]])
#   grid.get_matrix  # => [[10, 20], [10, 30]]
#   # The 10 auto-spans 2 rows because the nested grid has 2 rows

module CrymbleUI
  module RecursiveGridData
    alias Index = Tuple(Int32, Int32)  # {row, col}, also used for bounding (min and/or max)

    class Grid(T)
      @@version = 0  # caching helper
      @@mutex = Mutex.new
      @version = -1
      @input : Array(Array(T | Grid(T)))
      @offsets = {Array(Int32).new, Array(Int32).new}
      @elements = Array(Tuple(T, Index, Index, Grid(T), Index)).new  # {value, bounding_min, bounding_max, local_grid, local_index}
      @grids = Array(Tuple(Int32, Grid(T), Index, Index)).new  # {level, grid, bounding_min, bounding_max}

      def initialize(input = Array(Array(T | Grid(T))).new)  # default is an empty subgrid
        @input = input.map(&.map(&.as(T | Grid(T))))  # cast to uniform type
      end

      # Modify input with invalidation
      def replace(&) : Nil
        @input = yield(@input).map(&.map(&.as(T | Grid(T))))
        @@mutex.synchronize do
          @@version += 1
        end
      end

      # Get output size as {rows, cols}
      def size : Index
        update
        @offsets.map(&.[-1])
      end

      # Iterate over nested grids (DFS)
      # Block receives {level, grid, bounding_min, bounding_max}
      def grids(&)
        update
        @grids.each { |el| yield(el) }
      end

      # Iterate over flattened elements with their bounds
      # Block receives {value, bounding_min, bounding_max, local_grid, local_index}
      # bounding_min/max are inclusive row/col indices
      def elements(&)
        update
        @elements.each { |el| yield(el) }
      end

      # Convert to flattened 2D matrix (mainly for debugging & testing)
      def get_matrix : Array(Array(T | Nil))
        update
        matrix = Array(Array(T | Nil)).new
        size[0].times do
          matrix << [nil.as(T | Nil)] * size[1]
        end
        elements do |value, bounding_min, bounding_max, _local_grid, _local_index|
          (bounding_min[0]..bounding_max[0]).each do |ri|
            (bounding_min[1]..bounding_max[1]).each do |ci|
              matrix[ri][ci] = value
            end
          end
        end
        matrix
      end

      def inspect(io : IO) : Nil
        io << "Grid(" << @input << ")"
      end

      private def update
        if @version != @@version
          @@mutex.synchronize do
            @version = @@version
          end
          if @input.size > 0
            s = {@input.size, @input[0].size}
          else
            s = {0, 0}
          end
          calc_offsets(s)
          @elements = enumerate_elements
          @grids = enumerate_grids
        end
      end

      private def calc_offsets(s : Index)
        sizes = {Array.new(s[0], 1), Array.new(s[1], 1)}  # max sizes of individual rows and columns
        @input.each.with_index do |row, ri|
          raise("local input matrix needs to be rectangular") if row.size != s[1]
          row.each.with_index do |cell, ci|
            if cell.is_a?(Grid(T))
              sizes[0][ri] = {sizes[0][ri], cell.size[0]}.max
              sizes[1][ci] = {sizes[1][ci], cell.size[1]}.max
            end
          end
        end
        @offsets = sizes.map(&.accumulate(0))
      end

      protected def enumerate_elements : Array(Tuple(T, Index, Index, Grid(T), Index))
        elements = Array(Tuple(T, Index, Index, Grid(T), Index)).new
        @input.each.with_index do |row, ri|
          row.each.with_index do |cell, ci|
            if cell.is_a?(Grid(T))
              s = cell.size
              elements += cell.enumerate_elements.map do |value, bounding_min, bounding_max, local_grid, local_index|
                bounding_min, bounding_max = span(s, ri, ci, bounding_min, bounding_max)
                {value, bounding_min, bounding_max, local_grid, local_index}
              end
            else  # cell.is_a?(T)
              bounding_min, bounding_max = span({1, 1}, ri, ci, {0, 0}, {0, 0})
              elements << {cell.as(T), bounding_min, bounding_max, self, {ri, ci}}
            end
          end
        end
        elements
      end

      protected def enumerate_grids : Array(Tuple(Int32, Grid(T), Index, Index))
        grids = [{0, self, {0, 0}, {size[0] - 1, size[1] - 1}}]
        @input.each.with_index do |row, ri|
          row.each.with_index do |cell, ci|
            if cell.is_a?(Grid(T))
              s = cell.size
              grids += cell.enumerate_grids.map do |level, grid, bounding_min, bounding_max|
                bounding_min, bounding_max = span(s, ri, ci, bounding_min, bounding_max)
                {level + 1, grid, bounding_min, bounding_max}
              end
            end
          end
        end
        grids
      end

      private def span(s : Index, ri : Int32, ci : Int32, bounding_min : Index, bounding_max : Index) : Tuple(Index, Index)
        bounding_min = {@offsets[0][ri] + bounding_min[0], @offsets[1][ci] + bounding_min[1]}
        bounding_max = {
          bounding_max[0] == s[0] - 1 ? @offsets[0][ri + 1] - 1 : @offsets[0][ri] + bounding_max[0],
          bounding_max[1] == s[1] - 1 ? @offsets[1][ci + 1] - 1 : @offsets[1][ci] + bounding_max[1],
        }
        {bounding_min, bounding_max}
      end
    end
  end
end
