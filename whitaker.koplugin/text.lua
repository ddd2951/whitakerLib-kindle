-- INFO: A word as the book shows it, made into what the library looks up.
local Text = {}

local kFolds = {
  ["ā"] = "a", ["ē"] = "e", ["ī"] = "i", ["ō"] = "o", ["ū"] = "u", ["ȳ"] = "y",
  ["Ā"] = "A", ["Ē"] = "E", ["Ī"] = "I", ["Ō"] = "O", ["Ū"] = "U", ["Ȳ"] = "Y",
  ["ă"] = "a", ["ĕ"] = "e", ["ĭ"] = "i", ["ŏ"] = "o", ["ŭ"] = "u",
  ["Ă"] = "A", ["Ĕ"] = "E", ["Ĭ"] = "I", ["Ŏ"] = "O", ["Ŭ"] = "U",
  ["æ"] = "ae", ["Æ"] = "AE", ["œ"] = "oe", ["Œ"] = "OE",
}
local kCombiningMacron, kCombiningBreve = "\204\132", "\204\134"

-- INFO: The word with macrons, breves and ligatures folded to plain letters, or nil when other letters are left.
function Text.normalize(word)
  for from, to in pairs(kFolds) do word = word:gsub(from, to) end
  word = word:gsub(kCombiningMacron, ""):gsub(kCombiningBreve, "")
  if word == "" or word:find("[^A-Za-z]") then return nil end
  return word
end

return Text
