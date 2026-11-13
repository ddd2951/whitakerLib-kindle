-- INFO: Where sentences and words are in a text.
local Sentence = {}

local kAbbreviations = { m = true, c = true, cn = true, l = true, p = true, q = true, t = true,
  ti = true, sex = true, ser = true, sp = true, app = true, mam = true, kal = true,
  id = true, etc = true, cf = true, sc = true, cap = true }
local kPunctuation = {}
for _, char in ipairs({ "“", "”", "‘", "’", "«", "»", "—", "–", "…", " ", "\239\187\191" }) do
  kPunctuation[char] = true
end

-- INFO: The words of a text, each with its first and last byte and character.
function Sentence.words(text)
  local words, current, charIndex = {}, nil, 0
  for byte, char in text:gmatch("()([%z\1-\127\194-\244][\128-\191]*)") do
    charIndex = charIndex + 1
    local letter = char:match("^[A-Za-z]$") or (char:byte() >= 194 and not kPunctuation[char])
    if letter then
      if not current then
        current = { first = byte, firstChar = charIndex }
        words[#words + 1] = current
      end
      current.last, current.lastChar = byte + #char - 1, charIndex
    else
      current = nil
    end
  end
  for _, word in ipairs(words) do word.text = text:sub(word.first, word.last) end
  return words
end

-- INFO: The number of the word holding a character, or nil.
function Sentence.atChar(words, position)
  for index, word in ipairs(words) do
    if word.firstChar <= position and position <= word.lastChar then return index end
  end
end

-- INFO: A text cut into sentences at full stops, question and exclamation marks, past abbreviations,
--  initials and decimal points.
function Sentence.new(text)
  local model = { text = text, sentences = {} }
  local first, index = 1, 1
  local function add(last)
    local leading = text:sub(first, last):find("%S")
    if leading then
      local start = first + leading - 1
      local finish = last
      while finish >= start and text:sub(finish, finish):match("%s") do finish = finish - 1 end
      if text:sub(start, finish):find("[A-Za-z\128-\255]") then
        model.sentences[#model.sentences + 1] = { first = start, last = finish }
      end
    end
    first = last + 1
  end
  while index <= #text do
    local char = text:sub(index, index)
    if char == "." or char == "!" or char == "?" then
      local word = char == "." and text:sub(first, index):match("([A-Za-z]+)%.$")
      local abbreviated = word and (kAbbreviations[word:lower()] or #word == 1)
      local decimal = char == "." and text:sub(index - 1, index - 1):match("%d")
        and text:sub(index + 1, index + 1):match("%d")
      if not abbreviated and not decimal then
        while index < #text do
          local nextChar = text:sub(index + 1, index + 4):match("^([%z\1-\127\194-\244][\128-\191]*)")
          if nextChar and (nextChar:match("^[.!?\"')%]]$") or nextChar == "”" or nextChar == "’"
              or nextChar == "»") then
            index = index + #nextChar
          else break end
        end
        add(index)
      end
    end
    index = index + 1
  end
  add(#text)
  return model
end

-- INFO: The text of one sentence.
function Sentence.text(model, index)
  local sentence = model.sentences[index]
  return sentence and model.text:sub(sentence.first, sentence.last) or ""
end

return Sentence
