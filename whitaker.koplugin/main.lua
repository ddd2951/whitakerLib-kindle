-- INFO: The plugin: its menu item, the study view it opens on the book, and the lookup the view calls.
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local Whitaker = WidgetContainer:extend{ name = "whitaker", is_doc_only = true }

function Whitaker:init()
  self.ui.menu:registerToMainMenu(self)
end

function Whitaker:addToMainMenu(items)
  items.whitaker_words = {
    text = "WhitakerLib Reader", sorting_hint = "more_tools",
    enabled_func = function() return self:canStudyBook() end,
    callback = function() self:studyBook() end,
  }
end

local function reportError(err)
  logger.warn("WhitakerLib Kindle:", err)
  UIManager:show(InfoMessage:new{ text = tostring(err) })
end

function Whitaker:run(action)
  local ok, err = pcall(action)
  if not ok then reportError(err) end
  return ok
end

function Whitaker:canStudyBook()
  return self.ui.document ~= nil and self.ui.rolling ~= nil and self.ui.document.provider == "crengine"
end

function Whitaker:studyBook()
  self:run(function()
    if not self:canStudyBook() then error("No reflowable book is open.", 0) end
    self.text = dofile(self.path .. "/text.lua")
    self.sentence = dofile(self.path .. "/sentence.lua")
    self.format = dofile(self.path .. "/format.lua")
    local document = self.ui.document
    local position = self.ui.rolling:getBookLocation() or document:getXPointer()
    self.epub = dofile(self.path .. "/epub.lua")
    local source = self.epub.open(document, position, self.sentence)
    local Study = dofile(self.path .. "/sentence_view.lua")
    local view = Study:new{
      title = document.file:match("[^/]+$"), source = source, epub = self.epub, sentence = self.sentence,
      lookup = function(word) return self:lookup(word) end,
      on_error = reportError,
    }
    if self.study then self.study:onClose() end
    self.study = view
    view.close_callback = function()
      if self.study == view then self.study = nil end
      if self.ui.document == source.document and self.ui.rolling then
        self:run(function() self.ui.rolling:onGotoXPointer(source.current.position) end)
      end
    end
    UIManager:show(view)
  end)
end

function Whitaker:lookup(word)
  local plain = self.text.normalize(word)
  if not plain then return "Not looked up: unsupported letters." end
  if not self.backend then
    self.Backend = dofile(self.path .. "/backend.lua")
    self.backend = self.Backend.open(self.path)
  end
  return self.format.study(self.Backend.lookup(self.backend, plain))
end

return Whitaker
