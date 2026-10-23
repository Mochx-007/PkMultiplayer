-- The cartridge's own emote bubbles, out of the player's own ROM.
--
-- Gen2Recomped does not import Gen 2's emote sheet (data/sprites/emotes.asm:
-- SHOCK, QUESTION, HAPPY, SAD, HEART, BOLT, SLEEP, FISH, 16x16 2bpp each), so
-- the co-op emotes -- and every trainer's "!" -- fall back to drawn ones.  The
-- mod cannot ship the cartridge's art, but the player can hand the mod their
-- own ROM (manifest `required_imports`, the IMPORT button in the MODS panel).
-- From it the eight bubbles (512 bytes) are cut once, written as a PNG into
-- this mod's storage in the save folder, and registered where the field and
-- the co-op emotes look for them: `data.field.emotionBubbles`, the same shape
-- the Gen 1 extractor writes.  Without the ROM nothing changes.

local Emotes = {}

Emotes.IMPORT_ID = "johto_rom"
Emotes.FILE_NAME = "gen2_emotes.png"

-- Where ShockEmote sits; the other seven follow, 64 bytes apart.  Addresses,
-- not data: the same numbers the engine's own ROM manifests list
-- (tools/rom_manifest_<version>.json).
local LAYOUT = {
  ["POKEMON_GLD"] = { bank = 0x05, address = 0x4409 },
  ["POKEMON_SLV"] = { bank = 0x05, address = 0x4409 },
  ["PM_CRYSTAL"] = { bank = 0x41, address = 0x4350 },
}

-- The canonical dumps, the only ones these addresses are right for
-- (src/core/GameVersion.lua).
local SHA1 = {
  ["d8b8a3600a465308c9953dfa04f0081c05bdcb94"] = true, -- Gold
  ["49b163f7e57702bc939d642a18f591de55d92dae"] = true, -- Silver
  ["f2f52230b536214ef7c9924f483392993e226cfb"] = true, -- Crystal (Rev 1)
  ["f4cd194bdee0d04ca4eac29e09b8e4e9d818c133"] = true, -- Crystal (Rev 0)
}

local NAMES = { "shock", "question", "happy", "sad", "heart", "bolt", "sleep", "fish" }
local EMOTE_BYTES = 64

-- The bubbles' rects in the sheet, in EMOTE_* order.
function Emotes.bubbles()
  local out = {}
  for i, name in ipairs(NAMES) do
    out[i] = { name = name, x = (i - 1) * 16, y = 0, w = 16, h = 16 }
  end
  return out
end

-- The cartridge title in the header (0x134, up to 16 bytes, NUL-padded).
function Emotes.title(rom)
  return (rom:sub(0x135, 0x144):gsub("%z.*$", ""):match("^[%w_]+"))
end

-- The eight bubbles' 2bpp bytes, or nil + why.  `sha1hex` is optional (it
-- needs love.data); a title the layout does not know is refused either way.
function Emotes.raw(rom, sha1hex)
  if type(rom) ~= "string" or #rom ~= 0x200000 then return nil, "not a 2 MB Gen 2 ROM" end
  local title = Emotes.title(rom) or ""
  local layout
  for prefix, at in pairs(LAYOUT) do
    if title:sub(1, #prefix) == prefix then layout = at end
  end
  if not layout then return nil, "not Gold, Silver or Crystal (" .. title .. ")" end
  if sha1hex and not SHA1[sha1hex] then
    return nil, "not a canonical Gold / Silver / Crystal dump"
  end
  local offset = layout.bank * 0x4000 + (layout.address - 0x4000)
  return rom:sub(offset + 1, offset + #NAMES * EMOTE_BYTES)
end

-- The sheet (128x16 ImageData) from the bubbles' bytes, decoded by the
-- engine's own 2bpp reader so it matches what an importer would have written.
function Emotes.sheet(raw)
  local ImageWriter = require("src.import.ImageWriter")
  local sheet = ImageWriter.blank(#NAMES * 16, 16, 1, 1, 1, 0)
  for i = 1, #NAMES do
    -- decode2bpp takes a list of byte values, as the importer's Rom:bytes gives
    local bytes = { raw:byte((i - 1) * EMOTE_BYTES + 1, i * EMOTE_BYTES) }
    local img = ImageWriter.decode2bpp(bytes, 16, 16, true)
    ImageWriter.blit(sheet, img, (i - 1) * 16, 0)
  end
  return sheet
end

-- Make sure the sheet exists (cutting it from the imported ROM the first
-- time) and register it.  Returns the sheet's path, or nil + why.
-- No ROM imported: this mod's own drawn bubbles, laid out as the sheet.
--
-- Reported from play: "the NPCs use the old emote system".  Without the
-- cartridge's sheet the co-op emotes fell back to the drawn bubbles, while a
-- trainer's "!" -- drawn by the field -- fell back to its own plain box, and
-- the following Pokemon's find to yet another bubble: three looks for one
-- thing.  Registered as the sheet, the drawn bubbles are what all of them
-- draw.  The cartridge's slot 8 (the fishing bubble) has no drawn art; it
-- borrows the "!".  `pkmDrawn` lets a ROM imported later take over.
Emotes.DRAWN_FILE = "gen2_emotes_drawn_v1.png"

function Emotes.installDrawn(mod, field)
  local fs = love and love.filesystem
  if not (fs and love.image and love.image.newImageData) then return nil, "no images" end
  local okC, CoopEmotes = pcall(require, "src.coop.CoopEmotes")
  if not okC then return nil, "no drawn bubbles: " .. tostring(CoopEmotes) end
  local dir = "modstorage/" .. tostring(mod.id or "PkMultiplayer")
  local path = dir .. "/" .. Emotes.DRAWN_FILE
  if not fs.getInfo(path, "file") then
    local sheet = love.image.newImageData(#NAMES * 16, 16)
    for i = 1, #NAMES do
      local e = CoopEmotes.forBubble(i)
      local one = CoopEmotes.drawnBubbleData(e and e.id or "exclaim")
      if one then sheet:paste(one, (i - 1) * 16, 0, 0, 0, 16, 16) end
    end
    fs.createDirectory(dir)
    local ok, err = fs.write(path, sheet:encode("png"):getString())
    if not ok then return nil, "could not write " .. path .. ": " .. tostring(err) end
  end
  field.emotionBubbles = { path = path, bubbles = Emotes.bubbles(), pkmDrawn = true }
  return path
end

function Emotes.install(mod, data)
  local field = data and data.field
  if not field then return nil, "no field data" end
  if type(field.emotionBubbles) == "table" and field.emotionBubbles.path
     and not field.emotionBubbles.pkmDrawn then
    -- this Gen2Recomped (or another mod) already has them
    return field.emotionBubbles.path
  end
  local fs = love and love.filesystem
  if not fs then return nil, "no filesystem" end
  local dir = "modstorage/" .. tostring(mod.id or "PkMultiplayer")
  local path = dir .. "/" .. Emotes.FILE_NAME

  if not fs.getInfo(path, "file") then
    local imports = mod.imports
    local romPath = imports and imports.path and imports:path(Emotes.IMPORT_ID)
    local rom = romPath and mod:read(romPath)
    if not rom then
      if type(field.emotionBubbles) == "table" and field.emotionBubbles.pkmDrawn then
        return field.emotionBubbles.path
      end
      return Emotes.installDrawn(mod, field)
    end
    local sha1hex
    if love.data and love.data.hash and love.data.encode then
      sha1hex = love.data.encode("string", "hex", love.data.hash("sha1", rom)):lower()
    end
    local raw, why = Emotes.raw(rom, sha1hex)
    rom = nil
    if not raw then return nil, why end
    local png = Emotes.sheet(raw):encode("png"):getString()
    fs.createDirectory(dir)
    local ok, err = fs.write(path, png)
    if not ok then return nil, "could not write " .. path .. ": " .. tostring(err) end
  end

  field.emotionBubbles = { path = path, bubbles = Emotes.bubbles() }
  return path
end

return Emotes
