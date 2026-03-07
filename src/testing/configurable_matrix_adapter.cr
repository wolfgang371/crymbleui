# Configurable matrix adapter that generates hierarchical headers with merged cells.
#
# Grid math (given config nrhl, nchl, rhs, chs, lrs, lcs):
#   data_rows = rhs^nrhl * lrs
#   data_cols = chs^nchl * lcs
#   total_rows = nchl + data_rows   (col header rows + data rows)
#   total_cols = nrhl + data_cols   (row header cols + data cols)
#
# Header merges at level l (0-indexed, 0=outermost):
#   Row headers (col l, rows nchl..total_rows-1): each spans rhs^(nrhl-1-l) * lrs rows
#   Col headers (row l, cols nrhl..total_cols-1): each spans chs^(nchl-1-l) * lcs cols
#
# Corner cells (row < nchl AND col < nrhl): empty.
class ConfigurableMatrixAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  getter data_rows : Int32
  getter data_cols : Int32
  getter total_rows : Int32
  getter total_cols : Int32

  # Header config per axis: {num_levels, branching_factor, leaf_span}
  @row_hdr : {Int32, Int32, Int32}
  @col_hdr : {Int32, Int32, Int32}

  @data : Hash(Tuple(Int32, Int32), String)

  def initialize(nrhl, nchl, rhs, chs, lrs, lcs)
    @row_hdr = {nrhl, rhs, lrs}
    @col_hdr = {nchl, chs, lcs}
    @data_rows = rhs ** nrhl * lrs
    @data_cols = chs ** nchl * lcs
    @total_rows = nchl + @data_rows
    @total_cols = nrhl + @data_cols
    @data = Hash(Tuple(Int32, Int32), String).new { |h, k| h[k] = default_value(k[0], k[1]) }
  end

  private def nrhl; @row_hdr[0]; end
  private def nchl; @col_hdr[0]; end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    bg = if row < nchl && col < nrhl
           CrymbleUI::Color.new(180, 180, 180, 255)
         elsif row < nchl
           CrymbleUI::Color.new(255, 220, 180, 255)
         elsif col < nrhl
           CrymbleUI::Color.new(180, 210, 255, 255)
         else
           CrymbleUI::Color.new(255, 255, 255, 255)
         end
    CrymbleUI::TextInput.new(
      value: @data[{row, col}],
      mode: CrymbleUI::TextInputMode::QuickEntry,
      background_color: bg,
    ) { |value| @data[{row, col}] = value }
  end

  # Data rows/cols scroll out first, then header rows/cols at tail (sticky).
  # Tail must be descending [n-1, ..., 1, 0] so derive_sticky_count
  # sees 0 first (reverse scan) and builds {0} → {0,1} → … → {0..n-1}.
  def get_scrollorder : {Array(Int32), Array(Int32)}
    rows = if nchl == 0
      (0...@total_rows).to_a
    else
      (nchl...@total_rows).to_a + (0...nchl).to_a.reverse
    end
    cols = if nrhl == 0
      (0...@total_cols).to_a
    else
      (nrhl...@total_cols).to_a + (0...nrhl).to_a.reverse
    end
    {rows, cols}
  end

  def get_sizes : {Array(Float64), Array(Float64)}
    row_heights = Array.new(@total_rows, DEFAULT_ROW_HEIGHT)
    col_widths = Array.new(@total_cols, DEFAULT_COLUMN_WIDTH)
    nchl.times { |r| row_heights[r] = 1.5_f64 }
    nrhl.times { |c| col_widths[c] = 3.0_f64 }
    {row_heights, col_widths}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    if row < nchl && col < nrhl
      # Corner cell
      nrhl > 1 ? { {row, 0}, {row, nrhl - 1} } : { {row, col}, {row, col} }
    elsif col < nrhl && row >= nchl
      # Row header
      span = header_span(@row_hdr, col)
      start_row = nchl + ((row - nchl) // span) * span
      span > 1 ? { {start_row, col}, {start_row + span - 1, col} } : { {row, col}, {row, col} }
    elsif row < nchl && col >= nrhl
      # Col header
      span = header_span(@col_hdr, row)
      start_col = nrhl + ((col - nrhl) // span) * span
      span > 1 ? { {row, start_col}, {row, start_col + span - 1} } : { {row, col}, {row, col} }
    else
      { {row, col}, {row, col} }
    end
  end

  private def default_value(row : Int32, col : Int32) : String
    if row < nchl && col < nrhl
      ""
    elsif row < nchl
      level = row
      span = header_span(@col_hdr, level)
      "c#{level + 1}#{index_to_letters((col - nrhl) // span)}"
    elsif col < nrhl
      level = col
      span = header_span(@row_hdr, level)
      "r#{level + 1}#{index_to_letters((row - nchl) // span)}"
    else
      "(#{row - nchl},#{col - nrhl})"
    end
  end

  private def index_to_letters(i : Int32) : String
    result = "a"
    i.times { result = result.succ }
    result
  end

  # Header span at level l: branching^(num_levels-1-l) * leaf_span
  private def header_span(hdr : {Int32, Int32, Int32}, level : Int32) : Int32
    levels, branching, leaf = hdr
    branching ** (levels - 1 - level) * leaf
  end
end
