local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextViewer = require("ui/widget/textviewer")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local Study = InputContainer:extend{ covers_fullscreen = true }

local function chars(text) return select(2, text:gsub("[^\128-\191]", "")) end

-- INFO: Shows a pane's text from its top.
local function setText(pane, text)
  local box = pane.text_widget
  if box.text ~= text then box.charlist = nil end
  box:setText(text)
  box:scrollToTop()
  pane:resetScroll()
  pane:updateScrollBar()
end

-- INFO: Highlights in a pane the characters range() gives, first and last, or nothing when it gives none.
local function highlight(pane, range)
  pane.text_widget.updateHighlight = function(box)
    local first, last = range()
    box.highlight_rects = nil
    if first then
      local top = box.virtual_line_num
      local bottom = math.min(#box.vertical_string_list, top + box.lines_per_page - 1)
      if box.use_xtext then
        for line = top, bottom do box:_shapeLine(box.vertical_string_list[line]) end
        box.highlight_rects = box:getXtextHighlightRects(first, last, top, bottom)
      else
        box.highlight_rects = box:getNonXtextHighlightRects(first, last, top, bottom)
      end
    end
    return true
  end
end

local function redraw(pane)
  pane.text_widget:updateHighlight()
  pane.text_widget:redrawHighlight()
end

-- INFO: The character a tap in a pane falls on, or nil outside its text.
local function tappedChar(pane, gesture)
  local box = pane.text_widget
  local x, y = gesture.pos.x - box.dimen.x, gesture.pos.y - box.dimen.y
  if x >= 0 and x < box.width and y >= 0 and y < box.height then return box:getCharPosAtXY(x, y) end
end

function Study:init()
  self.states = {}
  local padding, gap = Screen:scaleBySize(8), Screen:scaleBySize(6)
  self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
  local width = self.dimen.w - 2 * padding
  self.titlebar = TitleBar:new{
    title = self.title, subtitle = "Tap a word", width = width, fullscreen = true,
    close_callback = function() self:onClose() end, show_parent = self,
  }
  self.buttons = ButtonTable:new{ width = width, show_parent = self, buttons = {
    {
      { text = "↓ Form", callback = function() self:stepForm(1) end },
      { text = "← Sentence", id = "previous", callback = function() self:move(-1) end },
      { text = "Sentence →", id = "next", callback = function() self:move(1) end },
      { text = "↑ Form", callback = function() self:stepForm(-1) end },
    },
    {
      { text = "← Word", callback = function() self:stepWord(-1) end },
      { text = "Report", callback = function() self:showFull() end },
      { text = "Word →", callback = function() self:stepWord(1) end },
    },
  } }
  local rule = Screen:scaleBySize(1)
  local function divider() return LineWidget:new{ dimen = Geom:new{ w = width, h = rule } } end
  local available = self.dimen.h - 2 * padding - self.titlebar:getHeight() - self.buttons:getSize().h
    - 5 * gap - 2 * rule
  local function pane(height, size, highlights)
    local function make(h)
      return ScrollTextWidget:new{ text = "", width = width, height = h, face = Font:getFace("cfont", size),
        dialog = self, highlight_text_selection = highlights }
    end
    local lineHeight = make(height):getLineHeight()
    local whole = math.floor(height / lineHeight) * lineHeight
    return make(whole), whole
  end
  local latinHeight, meaningsHeight, formHeight
  self.latin, latinHeight = pane(math.floor(available * 0.28), 22, true)
  self.meanings, meaningsHeight = pane(math.floor(available * 0.50), 19, true)
  self.form, formHeight = pane(available - latinHeight - meaningsHeight, 19, false)
  local leftover = available - latinHeight - meaningsHeight - formHeight

  local study = self
  self.latin.onTapScrollText = function(_, _, gesture) return study:tapWord(gesture) end
  self.meanings.onTapScrollText = function(_, _, gesture) return study:tapMeaning(gesture) end
  self.form.onTapScrollText = function() return true end
  highlight(self.latin, function()
    local word = study.words and study.words[study.selected]
    if word then return word.firstChar, word.lastChar end
  end)
  highlight(self.meanings, function()
    local range = study.meaningRange
    if range then return range[1], range[2] end
  end)
  self[1] = FrameContainer:new{
    padding = padding, margin = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
    VerticalGroup:new{ align = "left", self.titlebar, self.latin,
      VerticalSpan:new{ width = gap }, divider(), VerticalSpan:new{ width = gap }, self.meanings,
      VerticalSpan:new{ width = gap }, divider(), VerticalSpan:new{ width = gap }, self.form,
      VerticalSpan:new{ width = gap + leftover }, self.buttons },
  }
  if Device:hasKeys() then self.key_events.Close = {{ Device.input.group.Back }} end
  self:showSentence()
end

-- INFO: What the view remembers per sentence while it is open: scroll and selected word.
function Study:state()
  local key = self.source.current.position
  self.states[key] = self.states[key] or {}
  return self.states[key]
end

function Study:remember()
  local state = self:state()
  state.latinLine = self.latin.text_widget.virtual_line_num
  state.selected = self.selected
end

local function lineOf(box, char)
  local line
  for number, laidOut in ipairs(box.vertical_string_list) do
    if laidOut.offset and laidOut.offset > char then break end
    line = number
  end
  return line
end

-- INFO: Scrolls a pane to the line holding a character, if that line is out of view.
function Study:showChar(pane, char)
  local box = pane.text_widget
  local line = lineOf(box, char)
  if line and (line < box.virtual_line_num or line >= box.virtual_line_num + box.lines_per_page) then
    box:scrollLines(line - box.virtual_line_num)
    pane:updateScrollBar()
    UIManager:setDirty(self, "ui")
  end
end

function Study:forms()
  return self.result and self.result.forms or {}
end

-- INFO: The meanings pane: the word, then each meaning under its part of speech. self.ranges holds, by meaning
--  number, where its text starts and ends.
function Study:showMeanings(word, message)
  self.shownWord, self.shownMessage = word, message
  self.ranges, self.meaningRange = {}, nil
  local result = self.result
  if not result or result.count == 0 then
    setText(self.meanings, message or ("No readings found for “" .. word .. "”."))
  else
    local lines, length = {}, 0
    local function add(line)
      lines[#lines + 1] = line
      length = length + chars(line) + 1
    end
    add(word .. " · " .. #result.meanings .. (#result.meanings == 1 and " meaning" or " meanings"))
    if result.trimmed then add("Less likely readings were trimmed.") end
    for _, note in ipairs(result.notes) do add(note) end
    local part
    for number, meaning in ipairs(result.meanings) do
      if meaning.part ~= part then
        part = meaning.part
        add(part .. ":")
      end
      self.ranges[number] = { length + 3, length + 2 + chars(meaning.text) }
      add("• " .. meaning.text)
    end
    setText(self.meanings, table.concat(lines, "\n"))
  end
  UIManager:setDirty(self, "ui")
end

-- INFO: The form pane shows one form; its meaning is highlighted above.
function Study:selectForm(index)
  local forms = self:forms()
  if #forms == 0 then
    self.formIndex, self.meaningRange = nil, nil
    setText(self.form, "")
  else
    index = math.max(1, math.min(index, #forms))
    self.formIndex = index
    local form = forms[index]
    local header = "Form " .. index .. " of " .. #forms
    local count = #form.readings
    header = header .. " · " .. count .. (count == 1 and " reading" or " readings")
    setText(self.form, header .. "\n" .. table.concat(form.lines, "\n"))
    self.meaningRange = self.ranges[form.meaning]
  end
  redraw(self.meanings)
  UIManager:setDirty(self, "ui")
end

-- INFO: The next or previous form.
function Study:stepForm(direction)
  if self.formIndex then self:selectForm(self.formIndex + direction) end
end

-- INFO: The whole word in one scrollable text, as the plugin first showed it: each part, each meaning, its forms.
function Study:showFull()
  if not self.result or not self.result.full then return end
  local viewer
  local side = math.floor(Screen:getWidth() * 0.28)
  viewer = TextViewer:new{ title = self.result.word, text = self.result.full, buttons_table = {{
    { text = "↓ Page", width = side, callback = function() viewer.scroll_widget:onScrollDown() end },
    { text = "Close", callback = function() viewer:onClose() end },
    { text = "↑ Page", width = side, callback = function() viewer.scroll_widget:onScrollUp() end },
  }} }
  UIManager:show(viewer)
end

function Study:tapMeaning(gesture)
  local char = tappedChar(self.meanings, gesture)
  if not char then return true end
  for meaning, range in ipairs(self.ranges or {}) do
    if char >= range[1] and char <= range[2] then
      for index, form in ipairs(self:forms()) do
        if form.meaning == meaning then self:selectForm(index); break end
      end
      break
    end
  end
  return true
end

function Study:selectWord(index)
  local word = self.words[index]
  if not word then return end
  local ok, result = pcall(self.lookup, word.text)
  self.selected = index
  self.result = ok and type(result) == "table" and result or nil
  self:showMeanings(word.text, not self.result and (word.text .. "\n\n" .. tostring(result)) or nil)
  self:selectForm(1)
  self:showChar(self.latin, word.firstChar)
  redraw(self.latin)
end

-- INFO: The next or previous word; past either end of the sentence, the first or last word of the next one.
function Study:stepWord(direction)
  local index = (self.selected or (direction > 0 and 0 or #self.words + 1)) + direction
  if self.words[index] then return self:selectWord(index) end
  local before = self.source.current
  self:move(direction)
  if self.source.current ~= before then self:selectWord(direction > 0 and 1 or #self.words) end
end

function Study:tapWord(gesture)
  local char = tappedChar(self.latin, gesture)
  local index = char and self.sentence.atChar(self.words, char)
  if index then self:selectWord(index) end
  return true
end

function Study:showSentence()
  local text = self.source.current.text
  self.words, self.selected, self.result = self.sentence.words(text), nil, nil
  setText(self.latin, text)
  local state = self:state()
  if state.latinLine and state.latinLine > 1 then
    self.latin.text_widget:scrollLines(state.latinLine - 1)
    self.latin:updateScrollBar()
  end
  self:showMeanings(nil, "Tap a word above to see its meanings.")
  self:selectForm(1)
  if state.selected then self:selectWord(state.selected) else redraw(self.latin) end
  self.titlebar:setSubTitle(self.source.current.label)
  local previous, nextButton = self.buttons:getButtonById("previous"), self.buttons:getButtonById("next")
  if self.epub.canMove(self.source, -1) then previous:enable() else previous:disable() end
  if self.epub.canMove(self.source, 1) then nextButton:enable() else nextButton:disable() end
  UIManager:setDirty(self, "ui")
end

function Study:move(direction)
  self:remember()
  local ok, moved = pcall(self.epub.move, self.source, direction)
  if not ok then if self.on_error then self.on_error(moved) end; return end
  if moved then self:showSentence() end
end

function Study:onShow()
  UIManager:setDirty(self, "full")
  return true
end

function Study:paintTo(buffer, x, y)
  buffer:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
  InputContainer.paintTo(self, buffer, x, y)
end

function Study:onClose()
  UIManager:close(self)
  if self.close_callback then self.close_callback() end
  return true
end

function Study:onCloseWidget()
  self:free()
  UIManager:setDirty(nil, "full")
end

return Study
