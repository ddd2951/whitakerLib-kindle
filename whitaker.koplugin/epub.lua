-- INFO: The open book as a source of sentences: a window of its text nodes around the current place, and moving
--  through it sentence by sentence, reading more nodes at either end as needed.
local Epub = {}

local kMaxSectionBytes, kMaxSectionNodes = 512 * 1024, 2048

-- INFO: A position ("…/text().12") as its node path and character offset.
local function splitPosition(position)
  local path, offset = position:match("^(.-)%.(%d+)$")
  return path, tonumber(offset)
end

-- INFO: The text node at a position, or the next visible one, with the byte where each character starts.
local function readNode(document, position)
  local path = splitPosition(position)
  if not path or not path:match("/text%(%)[^/]*$") then
    position = document:getNextVisibleChar(position)
    if not position then return nil end
    path = splitPosition(position)
  end
  if not path then error("Cannot locate this EPUB text node.", 0) end
  local text = document:getTextFromXPointer(path .. ".0")
  if not text then error("Cannot read this EPUB text node.", 0) end
  if #text > kMaxSectionBytes then error("This EPUB text section exceeds 512 KiB.", 0) end
  local bytes = {}
  for byte in text:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do bytes[#bytes + 1] = byte end
  bytes[#bytes + 1] = #text + 1
  return { path = path, text = text, bytes = bytes, length = #bytes - 1 }
end

-- INFO: The visible text node before or after a node, or nil at the book's end.
local function adjacentNode(document, node, direction)
  local position
  if direction < 0 then position = document:getPrevVisibleChar(node.path .. ".0")
  else position = document:getNextVisibleChar(node.path .. "." .. node.length) end
  if not position then return nil end
  local adjacent = readNode(document, position)
  if adjacent and adjacent.path == node.path then error("Cannot advance through this EPUB section.", 0) end
  return adjacent
end

-- INFO: The nodes' text joined, with the whitespace the book has between them; sets each node's byte range.
local function windowText(document, nodes)
  local pieces, length = {}, 0
  for index, node in ipairs(nodes) do
    if index > 1 then
      local previous = nodes[index - 1]
      local gap = document:getTextFromXPointers(previous.path .. "." .. math.max(0, previous.length - 1),
        node.path .. "." .. math.min(1, node.length))
      if not gap then error("Cannot read the boundary between EPUB text nodes.", 0) end
      gap = gap:gsub("[^%s]", "")
      if previous.text:sub(-1):match("%s") then gap = gap:sub(2) end
      if node.text:sub(1, 1):match("%s") then gap = gap:sub(1, -2) end
      pieces[#pieces + 1], length = gap, length + #gap
    end
    node.first, node.last = length + 1, length + #node.text
    pieces[#pieces + 1], length = node.text, length + #node.text
  end
  if length > kMaxSectionBytes or #nodes > kMaxSectionNodes then
    error("This EPUB section exceeds 512 KiB or 2,048 text nodes.", 0)
  end
  return table.concat(pieces)
end

-- INFO: Where in the joined text a book position is.
local function bytePosition(nodes, position)
  local path, offset = splitPosition(position)
  for _, node in ipairs(nodes) do
    if node.path == path then
      local byte = node.bytes[math.min(offset, node.length) + 1]
      return node.first + byte - 1
    end
  end
  error("Cannot find the reading position in this EPUB section.", 0)
end

-- INFO: The book position of a byte in the joined text.
local function bookPosition(nodes, byte)
  for _, node in ipairs(nodes) do
    if byte >= node.first and byte <= node.last then
      local localByte = byte - node.first + 1
      local low, high = 1, #node.bytes
      while low < high do
        local middle = math.floor((low + high + 1) / 2)
        if node.bytes[middle] <= localByte then low = middle else high = middle - 1 end
      end
      return node.path .. "." .. (low - 1)
    end
  end
  error("Cannot map this sentence back to the EPUB.", 0)
end

-- INFO: What the view shows of one sentence: its text, its place and its neighbours' places, and its page.
local function sentenceFrame(document, sentence, nodes, model, index)
  local range = model.sentences[index]
  local before, after = model.sentences[index - 1], model.sentences[index + 1]
  local frame = {
    text = sentence.text(model, index), position = bookPosition(nodes, range.first),
    previous = before and bookPosition(nodes, before.first),
    next = after and bookPosition(nodes, after.first),
  }
  local page = document:getPageFromXPointer(frame.position)
  frame.label = "Page " .. page .. " / " .. document:getPageCount()
  return frame
end

-- INFO: The source, at the sentence holding a position.
function Epub.open(document, position, sentence)
  local source = { document = document, sentence = sentence }
  Epub.load(source, position)
  return source
end

-- INFO: Reads nodes around a position until the sentence there has a sentence on either side, or the book ends.
function Epub.load(source, position)
  if not position or not source.document:isXPointerInDocument(position) then
    error("Cannot locate the current place in this book.", 0)
  end
  local node = readNode(source.document, position)
  if not node then error("There is no text after this book position.", 0) end
  local path = splitPosition(position)
  if path ~= node.path then position = node.path .. ".0" end
  local nodes, atStart, atEnd = { node }, false, false
  while true do
    local text = windowText(source.document, nodes)
    local model = source.sentence.new(text)
    local count = #model.sentences
    local selected = count
    local anchor = bytePosition(nodes, position)
    for index, range in ipairs(model.sentences) do
      if range.last >= anchor then selected = index; break end
    end
    local needBefore = count > 0 and selected <= 2 and not atStart
    local needAfter = selected >= count - 1 and not atEnd
    if not needBefore and not needAfter then
      if count == 0 then error("This part of the book contains no Latin words.", 0) end
      local frame = sentenceFrame(source.document, source.sentence, nodes, model, selected)
      source.window = { nodes = nodes, model = model, index = selected, atStart = atStart, atEnd = atEnd }
      source.current = frame
      return
    end
    if needBefore then
      local previous = adjacentNode(source.document, nodes[1], -1)
      if previous then table.insert(nodes, 1, previous) else atStart = true end
    end
    if needAfter then
      local following = adjacentNode(source.document, nodes[#nodes], 1)
      if following then nodes[#nodes + 1] = following else atEnd = true end
    end
  end
end

-- INFO: Whether there is a sentence before (-1) or after (1) the current one.
function Epub.canMove(source, direction)
  return source.current[direction < 0 and "previous" or "next"] ~= nil
end

-- INFO: To the sentence before or after, reading on when the window ends; false at the book's ends.
function Epub.move(source, direction)
  local position = source.current[direction < 0 and "previous" or "next"]
  if not position then return false end
  local window = source.window
  local index = window.index + direction
  if (index > 1 or window.atStart) and (index < #window.model.sentences or window.atEnd) then
    local frame = sentenceFrame(source.document, source.sentence, window.nodes, window.model, index)
    window.index, source.current = index, frame
  else Epub.load(source, position) end
  return true
end

return Epub
