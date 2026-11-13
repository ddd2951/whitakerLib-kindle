local C = require("ffi").C

local parts, pronounKinds, grammarFields

-- HACK: Currently we remap them, wlib should instead provide better bindings
local function loadNames()
  parts = {
    [C.WHITAKER_PART_N] = "Noun",
    [C.WHITAKER_PART_PRON] = "Pronoun",
    [C.WHITAKER_PART_V] = "Verb",
    [C.WHITAKER_PART_ADJ] = "Adjective",
    [C.WHITAKER_PART_ADV] = "Adverb",
    [C.WHITAKER_PART_PREP] = "Preposition",
    [C.WHITAKER_PART_NUM] = "Numeral",
    [C.WHITAKER_PART_CONJ] = "Conjunction",
    [C.WHITAKER_PART_INTERJ] = "Interjection",
    [C.WHITAKER_PART_PACK] = "Pronoun",
    [C.WHITAKER_PART_SUPINE] = "Supine",
    [C.WHITAKER_PART_VPAR] = "Participle",
  }

  pronounKinds = {
    [C.WHITAKER_PRONOUN_KIND_PERS] = "personal pronoun",
    [C.WHITAKER_PRONOUN_KIND_REL] = "relative pronoun",
    [C.WHITAKER_PRONOUN_KIND_REFLEX] = "reflexive pronoun",
    [C.WHITAKER_PRONOUN_KIND_DEMONS] = "demonstrative pronoun",
    [C.WHITAKER_PRONOUN_KIND_INTERR] = "interrogative pronoun",
    [C.WHITAKER_PRONOUN_KIND_INDEF] = "indefinite pronoun",
    [C.WHITAKER_PRONOUN_KIND_ADJECT] = "pronominal adjective",
  }

  grammarFields = {
    {
      key = "comparison",
      names = {
        [C.WHITAKER_COMPARISON_POS] = "positive",
        [C.WHITAKER_COMPARISON_COMP] = "comparative",
        [C.WHITAKER_COMPARISON_SUPER] = "superlative",
      },
    },
    {
      key = "tense",
      names = {
        [C.WHITAKER_TENSE_PRES] = "present",
        [C.WHITAKER_TENSE_IMPF] = "imperfect",
        [C.WHITAKER_TENSE_FUT] = "future",
        [C.WHITAKER_TENSE_PERF] = "perfect",
        [C.WHITAKER_TENSE_PLUP] = "pluperfect",
        [C.WHITAKER_TENSE_FUTP] = "future perfect",
      },
    },
    {
      key = "voice",
      names = {
        [C.WHITAKER_VOICE_ACTIVE] = "active",
        [C.WHITAKER_VOICE_PASSIVE] = "passive",
      },
    },
    {
      key = "mood",
      names = {
        [C.WHITAKER_MOOD_IND] = "indicative",
        [C.WHITAKER_MOOD_SUB] = "subjunctive",
        [C.WHITAKER_MOOD_IMP] = "imperative",
        [C.WHITAKER_MOOD_INF] = "infinitive",
        [C.WHITAKER_MOOD_PPL] = "participle",
      },
    },
    {
      key = "person",
      names = {
        [1] = "1st person",
        [2] = "2nd person",
        [3] = "3rd person",
      },
    },
    {
      key = "gender",
      names = {
        [C.WHITAKER_GENDER_M] = "masculine",
        [C.WHITAKER_GENDER_F] = "feminine",
        [C.WHITAKER_GENDER_N] = "neuter",
        [C.WHITAKER_GENDER_C] = "common gender",
      },
    },
    {
      key = "number",
      names = {
        [C.WHITAKER_NUMBER_S] = "singular",
        [C.WHITAKER_NUMBER_P] = "plural",
      },
    },
    {
      key = "caseOf",
      names = {
        [C.WHITAKER_CASE_NOM] = "nominative",
        [C.WHITAKER_CASE_VOC] = "vocative",
        [C.WHITAKER_CASE_GEN] = "genitive",
        [C.WHITAKER_CASE_LOC] = "locative",
        [C.WHITAKER_CASE_DAT] = "dative",
        [C.WHITAKER_CASE_ABL] = "ablative",
        [C.WHITAKER_CASE_ACC] = "accusative",
      },
    },
    {
      key = "numeralSort",
      names = {
        [C.WHITAKER_NUMERAL_SORT_CARD] = "cardinal",
        [C.WHITAKER_NUMERAL_SORT_ORD] = "ordinal",
        [C.WHITAKER_NUMERAL_SORT_DIST] = "distributive",
        [C.WHITAKER_NUMERAL_SORT_ADVERB] = "adverbial numeral",
      },
    },
  }
end

local function grammarLine(grammar)
  local labels = {}
  for _, field in ipairs(grammarFields) do
    local label = field.names[grammar[field.key]]
    if label then labels[#labels + 1] = label end
  end
  return table.concat(labels, ", ")
end

-- INFO: The class as a reader names it. WORDS' own classes say nothing to a reader: adjective 2 (Greek), verbs past 4
--  (irregular, named as such), 9 (abbreviations), a pronoun's number (its kind is shown instead).
local nth = { "1st", "2nd", "3rd", "4th", "5th" }
local function classLine(g, reading)
  if reading.dictionaryPart == C.WHITAKER_PART_PRON then return pronounKinds[reading.dictionaryKind] end
  if g.which == 0 or g.part == C.WHITAKER_PART_NUM then return nil end
  if g.part == C.WHITAKER_PART_V or g.part == C.WHITAKER_PART_SUPINE or g.part == C.WHITAKER_PART_VPAR then
    if g.which <= 4 then return nth[g.which] .. " conjugation" end
    return g.which < 9 and "irregular verb" or nil
  end
  if g.part == C.WHITAKER_PART_ADJ then
    return (g.which == 1 and "1st and 2nd declension") or (g.which == 3 and "3rd declension") or nil
  end
  return nth[g.which] and nth[g.which] .. " declension" or nil
end

local function formLines(readings, sharedAddons)
  local lines = {}
  for _, reading in ipairs(readings) do
    if #lines > 0 then lines[#lines + 1] = "" end

    local g = reading.grammar
    local why = reading.stem
    if reading.ending ~= "" then why = why .. "·" .. reading.ending end
    local class = classLine(g, reading)
    if class then why = why .. " · " .. class end
    if g.part ~= reading.dictionaryPart then why = (parts[g.part] or reading.part) .. ": " .. why end
    lines[#lines + 1] = why

    local grammar = grammarLine(g)
    if grammar ~= "" then lines[#lines + 1] = grammar end

    if reading.dictionaryWordId == C.WHITAKER_NO_DICTIONARY_WORD and reading.numeralValue > 0 then
      lines[#lines + 1] = "Value: " .. reading.numeralValue
    end
    if not sharedAddons then
      for _, addon in ipairs(reading.addons) do
        lines[#lines + 1] = "Add-on “" .. addon.spelling .. "”: " .. addon.meaning
      end
    end
    if reading.syncope > 0 then lines[#lines + 1] = "Contracted perfect form, restored for this reading." end
    if reading.derivedAdverb then lines[#lines + 1] = "Adverb derived from an adjective." end
  end
  return lines
end

local Format = {}

-- INFO: A looked-up word as data for the view: its meanings once each, grouped by part of speech in the order the
--  library lists them, and its forms, one per dictionary word (its readings together), each pointing at its meaning
--  and in the order of the meanings. `full` is all of it as one text: each part, each meaning, its forms.
function Format.study(result)
  if not parts then loadNames() end
  local study = { word = result.word, count = #result.readings, trimmed = result.trimmed, notes = {},
    meanings = {}, forms = {} }
  if study.count == 0 then return study end

  -- NOTE: An add-on every reading has belongs to the whole word: one note, not one per form.
  local function addonsOf(reading)
    local ids = {}
    for _, addon in ipairs(reading.addons) do ids[#ids + 1] = addon.kind .. ":" .. addon.id end
    return table.concat(ids, " ")
  end
  local shared = addonsOf(result.readings[1])
  for _, reading in ipairs(result.readings) do
    if addonsOf(reading) ~= shared then shared = nil; break end
  end
  if shared == "" then shared = nil end
  if shared then
    for _, addon in ipairs(result.readings[1].addons) do
      study.notes[#study.notes + 1] = "Add-on “" .. addon.spelling .. "”: " .. addon.meaning
    end
  end

  local sections, byPart, byDictionaryWord = {}, {}, {}
  for _, reading in ipairs(result.readings) do
    local id = reading.dictionaryWordId
    local form = byDictionaryWord[id]
    if not form then
      local part = parts[reading.dictionaryPart] or reading.part
      local section = byPart[part]
      if not section then
        section = { part = part, meanings = {}, byMeaning = {} }
        byPart[part] = section
        sections[#sections + 1] = section
      end

      local meaning = section.byMeaning[reading.meaning]
      if not meaning then
        meaning = { text = reading.meaning, forms = {} }
        section.byMeaning[reading.meaning] = meaning
        section.meanings[#section.meanings + 1] = meaning
      end

      form = { dictionaryWordId = id, readings = {} }
      byDictionaryWord[id] = form
      meaning.forms[#meaning.forms + 1] = form
    end
    form.readings[#form.readings + 1] = reading
  end

  local lines = { study.count == 1 and "1 reading" or study.count .. " readings" }
  if study.trimmed then lines[#lines + 1] = "Less likely readings were trimmed." end
  for _, note in ipairs(study.notes) do lines[#lines + 1] = note end
  for _, section in ipairs(sections) do
    lines[#lines + 1] = ""
    lines[#lines + 1] = section.part
    for _, meaning in ipairs(section.meanings) do
      study.meanings[#study.meanings + 1] = { part = section.part, text = meaning.text }
      lines[#lines + 1] = "  " .. meaning.text
      for _, form in ipairs(meaning.forms) do
        form.meaning = #study.meanings
        form.lines = formLines(form.readings, shared)
        study.forms[#study.forms + 1] = form
        for _, line in ipairs(form.lines) do lines[#lines + 1] = "    " .. line end
      end
    end
  end
  study.full = table.concat(lines, "\n")
  return study
end

return Format
