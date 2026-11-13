local ffi = require("ffi")

local function text(pointer)
  return pointer ~= nil and ffi.string(pointer) or ""
end

local Backend = {}

function Backend.open(directory, libraryPath)
  if not pcall(ffi.typeof, "WhitakerResult") then
    local file = assert(io.open(directory .. "/whitaker_ffi.h", "r"))
    local declarations = file:read("*a")
    file:close()
    ffi.cdef(declarations)
  end
  local lib = ffi.load(libraryPath or directory .. "/libwhitaker.so.0")
  local result = lib.whitaker_result_new()
  if result == nil then error("Not enough memory to open the dictionary.", 0) end
  ffi.gc(result, function(pointer) lib.whitaker_result_free(pointer) end)
  return { lib = lib, result = result }
end

local kGrammarFields = {
  "part", "which", "variant", "caseOf", "number", "gender", "comparison",
  "numeralSort", "tense", "voice", "mood", "person",
}

function Backend.lookup(backend, word)
  local lib = backend.lib
  local status = tonumber(lib.whitaker_analyze(backend.result, word, #word))
  if status ~= ffi.C.WHITAKER_STATUS_OK then
    local messages = {
      [ffi.C.WHITAKER_STATUS_INPUT_TOO_LONG] = "Error: more than 24 letters",
      [ffi.C.WHITAKER_STATUS_OUT_OF_MEMORY] = "Error: not enough memory.",
    }
    error(messages[status] or "Error: lib failed.", 0)
  end

  local looked = { word = word, readings = {}, trimmed = lib.whitaker_trimmed(backend.result, 0) }
  for index = 0, tonumber(lib.whitaker_reading_count(backend.result, 0)) - 1 do
    local detail = lib.whitaker_detail(backend.result, 0, index)
    local grammar = {}
    for _, field in ipairs(kGrammarFields) do grammar[field] = tonumber(detail.form.grammar[field]) end

    local reading = {
      stem = ffi.string(detail.form.stemSpelling),
      ending = ffi.string(detail.form.ending),
      meaning = text(detail.meaning),
      part = text(detail.partName),
      grammar = grammar,
      dictionaryWordId = tonumber(detail.dictionaryWordId),
      dictionaryPart = tonumber(detail.dictionaryWord.part),
      dictionaryKind = tonumber(detail.dictionaryWord.kind),
      numeralValue = tonumber(detail.dictionaryWord.numeralValue),
      syncope = tonumber(detail.form.derivation.syncope),
      derivedAdverb = detail.form.derivation.adverb,
      addons = {},
    }

    for a = 0, tonumber(detail.addonCount) - 1 do
      local addon = detail.addons[a]
      reading.addons[#reading.addons + 1] = {
        kind = tonumber(addon.kind),
        id = tonumber(addon.id),
        spelling = text(lib.whitaker_addon_spelling(addon.id)),
        meaning = text(lib.whitaker_addon_meaning(addon.id)),
      }
    end
    looked.readings[#looked.readings + 1] = reading
  end

  return looked
end

return Backend
