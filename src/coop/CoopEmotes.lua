-- src/coop/CoopEmotes.lua
-- Co-op emotes, in one place: which there are, how they look, where they
-- hang, and the quick picker.
--
-- They are the cartridge's own bubbles -- the same sheet the field draws a
-- trainer's "!" from (field.emotionBubbles; Gen 2's eight are exported by
-- RomExtractorGen2) -- hung where the field hangs them: centred, sixteen
-- pixels above the owner's centre, with the bubble's little pop-in bounce.
-- A dataset without the sheet falls back to a drawn pill with the symbol.
--
-- Ids stay the ones the link already speaks ("exclaim", "heart", ...), so an
-- older partner still understands them; the two whose art changed map on
-- (music -> happy, star -> bolt).

local CoopEmotes = {}

CoopEmotes.LIST = {
  { id = "exclaim",  bubble = 1, sym = "!",  name = "SHOCK" },
  { id = "question", bubble = 2, sym = "?",  name = "QUESTION" },
  { id = "happy",    bubble = 3, sym = ":)", name = "HAPPY" },
  { id = "sad",      bubble = 4, sym = ":(", name = "SAD" },
  { id = "heart",    bubble = 5, sym = "<3", name = "HEART" },
  { id = "bolt",     bubble = 6, sym = "#",  name = "ANGRY" },
  { id = "sleep",    bubble = 7, sym = "Z",  name = "SLEEPY" },
}
local ALIAS = { music = "happy", star = "bolt" }

CoopEmotes.DURATION = 2.5

local byId = {}
for _, e in ipairs(CoopEmotes.LIST) do byId[e.id] = e end

function CoopEmotes.get(id)
  if type(id) ~= "string" then return nil end
  return byId[ALIAS[id] or id]
end

function CoopEmotes.valid(id)
  return CoopEmotes.get(id) ~= nil
end

local sheetCache = {}
local function sheet(game)
  local field = game and game.data and game.data.field
  local def = field and field.emotionBubbles
  if not (def and def.path and def.bubbles) then return nil end
  local hit = sheetCache[def.path]
  if hit == nil then
    local ok, img = pcall(function()
      local Assets = require("src.render.Assets")
      if not (love.image and love.image.newImageData) then return Assets.image(def.path) end
      -- the field's own OBJ-palette pass (OverworldController obpEmoteImage):
      -- colours 0/1 -> white, 2 -> light grey, 3 -> black, so these match
      -- the trainers' "!" exactly
      local id = Assets.imageData(def.path)
      id:mapPixel(function(_, _, r, _, _, a)
        local v = 0
        if r > 0.5 then v = 1 elseif r > 0.17 then v = 170 / 255 end
        return v, v, v, a
      end)
      local made = love.graphics.newImage(id)
      made:setFilter("nearest", "nearest")
      return made
    end)
    hit = (ok and img) or false
    sheetCache[def.path] = hit
  end
  if not hit then return nil end
  return hit, def.bubbles
end

local quads = {}
local function quadFor(img, rect, key)
  local q = quads[key]
  if not q then
    q = love.graphics.newQuad(rect.x, rect.y, rect.w, rect.h, img:getDimensions())
    quads[key] = q
  end
  return q
end

-- the field bubble's pop: up a few pixels and settle (frames since shown)
local function bounce(age)
  local t = math.floor((age or 0) * 60)
  if t < 4 then return -t end
  if t < 8 then return -(8 - t) end
  return 0
end

-- Draw emote `id` for an entity whose screen-space feet are at (fx, fy)
-- (bottom-centre of a 16x16 walker) and that has been up for `age` seconds.
function CoopEmotes.draw(game, id, fx, fy, age)
  local e = CoopEmotes.get(id)
  if not e then return end
  local cx = math.floor(fx)
  -- the owner's centre is 8 above the feet; the bubble's centre 16 above that
  local cy = math.floor(fy - 8 - 16 + bounce(age))
  local img, bubbles = sheet(game)
  local rect = bubbles and bubbles[e.bubble]
  if img and rect then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, quadFor(img, rect, tostring(img) .. e.bubble),
                       cx - math.floor(rect.w / 2), cy - math.floor(rect.h / 2))
    return
  end
  -- no sheet: a pill with the symbol, same anchor
  local MicroFont = require("src.render.MicroFont")
  local w = math.max(13, MicroFont.width(e.sym) + 6)
  local bx, by = cx - math.floor(w / 2), cy - 4
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", bx + 1, by, w - 2, 9)
  love.graphics.rectangle("fill", bx, by + 1, w, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", bx + 1, by + 1, w - 2, 7)
  love.graphics.setColor(0, 0, 0, 1)
  MicroFont.draw(e.sym, bx + 3, by + 2)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------
-- the quick picker: a strip of bubbles along the top, LEFT/RIGHT and A
-- ---------------------------------------------------------------------

local Picker = {}
Picker.__index = Picker
Picker.isOpaque = false
Picker.isEmotePicker = true

function CoopEmotes.newPicker(game, onPick)
  return setmetatable({ game = game, onPick = onPick, index = 1, timer = 0 }, Picker)
end

function Picker:update(dt)
  self.timer = self.timer + (dt or 0.016)
  local input = self.game.input
  if not input then return end
  local n = #CoopEmotes.LIST
  if input:wasPressed("left") or input:wasPressed("up") then
    self.index = (self.index - 2) % n + 1
  elseif input:wasPressed("right") or input:wasPressed("down") then
    self.index = self.index % n + 1
  elseif input:wasPressed("b") then
    self.game.stack:pop()
  elseif input:wasPressed("a") and self.timer > 0.1 then
    self.game.stack:pop()
    if self.onPick then self.onPick(CoopEmotes.LIST[self.index].id) end
  end
end

function Picker:draw()
  local Font = require("src.render.Font")
  local n = #CoopEmotes.LIST
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 0, 20, 6)
  local step = 20
  local x0 = math.floor((160 - (n - 1) * step) / 2)
  for i = 1, n do
    -- feet at y=40 puts each bubble's centre at y=16
    CoopEmotes.draw(self.game, CoopEmotes.LIST[i].id, x0 + (i - 1) * step, 40, 1)
  end
  -- the cursor under the picked one, and its name
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawCode(0xEE, x0 + (self.index - 1) * step - 4, 24)
  Font.draw(CoopEmotes.LIST[self.index].name, 8, 32)
  love.graphics.setColor(1, 1, 1, 1)
end

function CoopEmotes.openPicker(game)
  local ok, CM = pcall(require, "src.coop.CoopManager")
  if not (ok and CM and CM.connected) then return false end
  local top = game.stack:top()
  if top and top.isEmotePicker then return false end
  game.stack:push(CoopEmotes.newPicker(game, function(id) CM.sendEmote(id) end))
  return true
end

return CoopEmotes
