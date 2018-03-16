-- Copyright 2012-2018 The Howl Developers
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

{:PropertyObject} = howl.util.moon
{:highlight, :style, :StyledText} = howl.ui
{:Matcher} = howl.util
{:max, :min} = math
{:tostring} = _G

append = table.insert

style.define_default 'list_highlight', color: '#ffffff', underline: true

highlight.define_default 'list_selection', {
  type: highlight.RECTANGLE,
  color: '#888888'
  alpha: 50
  outline_alpha: 100
}

highlight.define_default 'list_selection', {
  type: highlight.UNDERLINE
  text_color: '#000000'
}

reversed = (list) -> [item for item in *list[#list, 1, -1]]

get_highlight_range = (content, hl) ->
  {:start_column, :end_column} = hl
  unless start_column
    if hl.start_index
      start_column = tostring(content)\char_offset(hl.start_index)
    else
      return nil

  unless end_column
    if hl.end_index
      end_column = tostring(content)\char_offset(hl.end_index)
    elseif hl.count
      end_column = start_column + hl.count
    else
      return nil

  start_column, end_column

get_items = (matcher, search) ->
  unless matcher
    return {}, false

  items, partial = matcher(search)
  items or {}, partial

class List extends PropertyObject
  new: (@matcher, opts={}) =>
    super!
    @opts = moon.copy opts

    with @opts
      .filler_text or= '~'

    @_max_rows = math.huge
    @_min_rows = 1
    @rows_shown = 0

    @_columns = { {} }
    @page_start_idx = 1
    @page_size = 1
    @column_widths = { 1 }
    @highlight_matches_for = nil
    @_items, @partial = get_items matcher, ''
    @selected_idx = @has_items and (@opts.reverse and #@_items or 1) or nil
    @listeners = {}

  @property columns:
    get: => @_columns
    set: (val) =>
      val = val or { {} }
      @_columns = val

  @property offset: get: => @page_start_idx

  @property items: get: => @_items

  @property headers:
    get: => [column.header for column in *@_columns]

  @property has_header:
    get: =>
      for header in *@headers
        return true if header
      return false

  @property has_items:
    get: => #@_items > 0

  @property selection:
    get: => @selected_idx and @_items and @_items[@selected_idx]
    set: (val) =>
      for idx, item in ipairs @_items
        if item == val
          @_select(idx)
          return
      error "cannot select - #{val} not found"

  @property max_rows:
    get: => @_max_rows
    set: (val) =>
      @_max_rows = val

      if @_min_rows > @_max_rows
        @_min_rows = @_max_rows

  @property min_rows:
    get: => @_min_rows
    set: (val) =>
      @_min_rows = val

  insert: (@buffer) =>
    @draw!
    if @selected_idx
      @_scroll_to @selected_idx

  draw: =>
    unless @buffer
      error "No buffer associated: call insert(buffer) first"

    @buffer\change 1, @buffer.size, (buffer) ->
      buffer.text = ''
      header_rows = (@has_header and 1 or 0)
      p_size = #@_items
      show_status = #@_items == 0
      display_size = p_size + header_rows + (show_status and 1 or 0)
      if display_size > @max_rows -- eventual headers + items > allowed
        p_size = @max_rows - header_rows - 1
        display_size = @max_rows
        show_status = true

      @page_size = p_size
      if @has_items and @page_size < 1
        error 'insufficient height - cant display any items'

      items = {}
      last_idx = @page_start_idx + @page_size - 1
      for idx = @page_start_idx, min(last_idx, #@_items)
        append items, @_items[idx]

      styled_table, col_starts = StyledText.for_table items, @columns
      buffer\append styled_table
      filler_lines = max 0, @min_rows - display_size

      for _ = 1, filler_lines
        buffer\append @opts.filler_text..'\n', 'comment'

      for lno = 1, #items
        line = buffer.lines[lno + header_rows]
        @_highlight_matches line.text, line.start_pos
        @_highlight_segments line.start_pos, items[lno], col_starts

      if show_status
        @_write_status!

      @rows_shown = max 1, display_size + filler_lines

    if @selected_idx
      @_highlight @selected_idx

    for listener in *@listeners
      pcall listener, @

  prev_page: =>
    local idx
    if @selected_idx == 1
      idx = #@_items
    else
      idx = max 1, @selected_idx - @page_size
    @_jump_to_page_at @page_start_idx + @page_size
    @_select idx

  next_page: =>
    local idx
    if @selected_idx == #@_items
      idx = 1
    else
      idx = min #@_items, @selected_idx + @page_size

    @_jump_to_page_at @page_start_idx + @page_size
    @_select idx

  select_prev: =>
    return unless @has_items
    @_select @selected_idx > 1 and @selected_idx - 1 or #@_items

  select_next: =>
    return unless @has_items
    @_select @selected_idx < #@_items and @selected_idx + 1 or 1

  update: (match_text, preserve_position=false) =>
    @_items, @partial = get_items @matcher, match_text
    current_idx = @selected_idx

    if @opts.reverse
      @_items = reversed @_items

    @highlight_matches_for = match_text

    @selected_idx = @has_items and (@opts.reverse and #@_items or 1) or nil

    if preserve_position and current_idx and @selected_idx
      @selected_idx = min(current_idx, #@_items)
      @_scroll_to @selected_idx

    @draw!

  on_refresh: (listener) =>
    @listeners[#@listeners + 1] = listener

  _highlight_segments: (start_pos, item, columns) =>
    return unless type(item) == 'table'
    highlights = item.item_highlights
    return unless highlights

    ranges = {}
    for col = 1, columns.num
      hls = highlights[col]
      continue unless hls
      offset = start_pos + columns[col] - 1
      for hl in *hls
        start_col, end_col = get_highlight_range(item[col], hl)
        if start_col
          ranges[#ranges + 1] = { offset + start_col - 1, end_col - start_col }

    hl_name = highlights.highlight or 'list_highlight'
    highlight.apply hl_name, @buffer, ranges

  _highlight_matches: (text, start_pos) =>
    if not @highlight_matches_for or @highlight_matches_for.is_empty
      return

    highlighter = self.highlighter or (t) ->
      explain = @opts.explain
      explain or= type(@matcher) == 'table' and @matcher.explain or Matcher.explain
      explain @highlight_matches_for, t

    segments = highlighter text
    if segments
      ranges = {}
      for segment in *segments
        ranges[#ranges + 1] = { start_pos + segment[1] - 1, segment[2] }

      highlight.apply 'list_highlight', @buffer, ranges

  _write_status: =>
    last_idx = @page_start_idx + @page_size - 1
    if #@_items < last_idx
      last_idx = #@_items

    status = '(no items)'
    if last_idx > 0
      qualifier = @partial and '+' or ''
      status = "showing #{@page_start_idx} to #{last_idx} out of #{#@_items}#{qualifier}"
      @buffer\append '[..] ', 'comment'

    @buffer\append "#{status}\n", 'comment'

  _select: (idx) =>
    if not @has_items
      @selected_idx = nil
      @_highlight nil
      return

    if idx < 1
      idx = 1
    elseif idx > #@_items
      idx = #@_items

    @selected_idx = idx

    if @buffer
      @_scroll_to idx
      @_highlight idx

    changed = @selection != @previous_selection
    @previous_selection = @selection

    if changed and @opts.on_selection_change
      @opts.on_selection_change @selection

  _scroll_to: (idx) =>
    if @page_start_idx <= idx and @page_start_idx + @page_size > idx
      return

    if idx < @page_start_idx
      @_jump_to_page_at idx
    elseif @page_start_idx + @page_size - 1 < idx
      @_jump_to_page_at idx - @page_size + 1

  _highlight: (idx) =>
    highlight.remove_all 'list_selection', @buffer
    return unless idx

    offset = idx - @page_start_idx + 1
    if offset < 1 or offset > @page_size
      return

    offset += 1 if @has_header

    lines = @buffer.lines
    pos = lines[offset].start_pos
    length = #lines[offset]
    highlight.apply 'list_selection', @buffer, pos, length

  _jump_to_page_at: (idx) =>
    start_of_last_page = #@_items - @page_size + 1
    if idx < 1
      idx = 1
    elseif idx > start_of_last_page
      idx = start_of_last_page

    @page_start_idx = idx
    @draw!