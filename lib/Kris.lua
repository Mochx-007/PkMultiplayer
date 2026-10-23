-- KRIS ON A GOLD OR SILVER SCREEN, out of the player's own Crystal ROM.
--
-- A Crystal partner who plays as Kris walks as SPRITE_KRIS, which Gold and
-- Silver do not have: their copy fell back to its own hero, so Kris showed up
-- as the boy (in Crystal's colour).  The mod cannot ship her art, but the ROM
-- the player imports for the emotes (manifest `required_imports`, johto_rom)
-- may be a Crystal one -- and Crystal carries her whole set.  From it three
-- sheets are cut once into this mod's storage, the same way lib/Emotes.lua
-- cuts the bubbles:
--
--   KrisSpriteGFX      $31:$7A40  the walking sheet, Chris's geometry (16x96)
--   KrisBikeSpriteGFX  $31:$7BC0  the bike sheet, right behind it
--   KrisBackpic        $22:$4ED6  raw 6x6, COLUMN-major (ChrisBackpic is LZ3;
--                                 hers is the odd raw one out)
--
-- The two sheets are registered as SPRITE_KRIS / SPRITE_KRIS_BIKE, each a copy
-- of this game's own hero record with Kris's pixels; the back pic is handed
-- to a co-op double whose partner is Kris (Kris.backPath).  A Crystal game
-- has her already and is left alone; without a Crystal ROM nothing changes.

local Kris = {}

Kris.IMPORT_ID = "johto_rom"

local SHEETS = {
  { id = "SPRITE_KRIS", like = "SPRITE_RED", bank = 0x31, address = 0x7A40,
    width = 16, height = 96, file = "kris_walk_v1.png" },
  { id = "SPRITE_KRIS_BIKE", like = "SPRITE_RED_BIKE", bank = 0x31, address = 0x7BC0,
    width = 16, height = 96, file = "kris_bike_v1.png" },
}
local BACK = { bank = 0x22, address = 0x4ED6, cols = 6, rows = 6, file = "kris_back_v1.png" }

-- the Crystal dumps these addresses are right for (src/core/GameVersion.lua)
local SHA1 = {
  ["f2f52230b536214ef7c9924f483392993e226cfb"] = true, -- Crystal (Rev 1)
  ["f4cd194bdee0d04ca4eac29e09b8e4e9d818c133"] = true, -- Crystal (Rev 0)
}

-- set by install: the back pic for a Kris partner, nil when there is none
Kris.backPath = nil

local function bytesAt(rom, bank, address, n)
  local offset = bank * 0x4000 + (address - 0x4000)
  return { rom:byte(offset + 1, offset + n) }
end

local function colMajorToRowMajor(pixels, cols, rows)
  local out = {}
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local src = (x * rows + y) * 16 + 1
      local dst = (y * cols + x) * 16 + 1
      for b = 0, 15 do out[dst + b] = pixels[src + b] end
    end
  end
  return out
end

-- The three images (walk, bike, back) as ImageData, or nil + why.  Decoded
-- by the engine's own 2bpp reader, the way its Crystal import writes them;
-- the back pic gets the white surround cut out like every other trainer pic.
function Kris.cut(rom, sha1hex)
  if type(rom) ~= "string" or #rom ~= 0x200000 then return nil, "not a 2 MB Gen 2 ROM" end
  local title = (rom:sub(0x135, 0x144):gsub("%z.*$", ""):match("^[%w_]+")) or ""
  if title:sub(1, 10) ~= "PM_CRYSTAL" then return nil, "not a Crystal ROM (" .. title .. ")" end
  if sha1hex and not SHA1[sha1hex] then return nil, "not a canonical Crystal dump" end
  local ImageWriter = require("src.import.ImageWriter")
  local out = {}
  for i, s in ipairs(SHEETS) do
    out[i] = ImageWriter.decode2bpp(bytesAt(rom, s.bank, s.address, s.width * s.height / 4),
                                    s.width, s.height)
  end
  local raw = bytesAt(rom, BACK.bank, BACK.address, BACK.cols * BACK.rows * 16)
  local back = ImageWriter.decode2bpp(colMajorToRowMajor(raw, BACK.cols, BACK.rows),
                                      BACK.cols * 8, BACK.rows * 8)
  out[#out + 1] = ImageWriter.matteColor0(back)
  return out
end

-- Make sure the sheets exist (cutting them from the imported ROM the first
-- time) and register them.  Returns true, or nil + why.
function Kris.install(mod, data)
  local sprites = data and data.sprites
  if type(sprites) ~= "table" then return nil, "no sprite data" end
  if sprites.SPRITE_KRIS and not sprites.SPRITE_KRIS.pkmKris then
    return nil, "this game has Kris already"
  end
  for _, s in ipairs(SHEETS) do
    if type(sprites[s.like]) ~= "table" then return nil, "no " .. s.like .. " to model her on" end
  end
  local fs = love and love.filesystem
  if not fs then return nil, "no filesystem" end
  local dir = "modstorage/" .. tostring(mod.id or "PkMultiplayer")
  local paths = {}
  for i, s in ipairs(SHEETS) do paths[i] = dir .. "/" .. s.file end
  paths[#paths + 1] = dir .. "/" .. BACK.file

  local missing = false
  for _, p in ipairs(paths) do
    if not fs.getInfo(p, "file") then missing = true end
  end
  if missing then
    local imports = mod.imports
    local romPath = imports and imports.path and imports:path(Kris.IMPORT_ID)
    local rom = romPath and mod:read(romPath)
    if not rom then return nil, "no ROM imported" end
    local sha1hex
    if love.data and love.data.hash and love.data.encode then
      sha1hex = love.data.encode("string", "hex", love.data.hash("sha1", rom)):lower()
    end
    local images, why = Kris.cut(rom, sha1hex)
    rom = nil
    if not images then return nil, why end
    fs.createDirectory(dir)
    for i, img in ipairs(images) do
      local ok, err = fs.write(paths[i], img:encode("png"):getString())
      if not ok then return nil, "could not write " .. paths[i] .. ": " .. tostring(err) end
    end
  end

  for i, s in ipairs(SHEETS) do
    local def = {}
    for k, v in pairs(sprites[s.like]) do def[k] = v end
    def.id, def.image, def.pkmKris = s.id, paths[i], true
    sprites[s.id] = def
  end
  Kris.backPath = paths[#paths]
  return true
end

return Kris
