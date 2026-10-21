-- src/coop/CoopChatBox.lua
-- Retro 2D Game Boy chat input modal.
-- Fits strictly within 160x144 (20x18 tiles), 100% English.
--
-- The upper half is the conversation -- the last few messages and, live, what
-- the partner is typing right now -- and the bottom two rows are yours.
-- Every change you make is reported to CoopManager.sendChatLive, so the
-- partner reads along letter by letter instead of waiting for ENTER.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")

local MAX_CHARS = 35   -- two input rows: 17 after the ">" plus 18
local LOG_ROWS = 4

local CoopChatBox = {}
CoopChatBox.__index = CoopChatBox
CoopChatBox.isChatBox = true
CoopChatBox.isOpaque = false

-- A phone types on the on-screen keyboard, which only shows while text
-- input is armed; a desktop has text input on all the time, and other tools
-- rely on it staying on, so only a phone has it lowered again.
local function isPhone()
  local name = love and love.system and love.system.getOS and love.system.getOS()
  return name == "iOS" or name == "Android"
end
CoopChatBox.isPhone = isPhone

local function setKeyboard(on)
  pcall(function()
    if love.keyboard and love.keyboard.setTextInput then
      love.keyboard.setTextInput(on)
    end
  end)
end

local function manager()
  local ok, CoopManager = pcall(require, "src.coop.CoopManager")
  return ok and CoopManager or nil
end

local function popUtf8Char(str)
  local len = #str
  if len == 0 then return "" end
  local b = str:byte(len)
  local drop = 1
  while len - drop > 0 and (b >= 0x80 and b <= 0xBF) do
    drop = drop + 1
    b = str:byte(len - drop + 1)
  end
  return str:sub(1, len - drop)
end

function CoopChatBox.new(game)
  local self = setmetatable({
    game = game,
    text = "",
    cursorTimer = 0,
    tx = 0,
    ty = 9,
    tw = 20,
    th = 9,
    -- the T that opened the box also arrives as text input right after;
    -- it must not become the first letter of the message
    swallowOpenKey = true,
  }, CoopChatBox)

  -- raises the on-screen keyboard on a phone
  setKeyboard(true)

  return self
end

-- the box going away without a message: the partner's typing line goes too
function CoopChatBox:cancel()
  local CM = manager()
  if CM and CM.sendChatLive then CM.sendChatLive(nil, true) end
  self:close()
end

function CoopChatBox:changed()
  local CM = manager()
  if CM and CM.sendChatLive then CM.sendChatLive(self.text) end
end

function CoopChatBox:close()
  if isPhone() then setKeyboard(false) end
  if self.game and self.game.stack then
    local top = type(self.game.stack.top) == "function" and self.game.stack:top() or self.game.stack.top
    if top == self then self.game.stack:pop() end
  end
end

function CoopChatBox:onTextInput(text)
  if not text or text == "" then return end
  if self.swallowOpenKey then
    self.swallowOpenKey = false
    if (text == "t" or text == "T") and self.text == "" then return end
  end
  -- Filter control characters
  local clean = text:gsub("[%c]", "")
  if clean == "" then return end

  if #self.text + #clean <= MAX_CHARS then
    self.text = self.text .. clean
    self:changed()
  end
end

function CoopChatBox:onKeyPressed(key)
  if key == "escape" then
    pcall(Sound.play, self.game.data, "Menu")
    self:cancel()
  elseif key == "backspace" then
    if #self.text > 0 then
      self.text = popUtf8Char(self.text)
      self:changed()
    end
  elseif key == "return" or key == "kpenter" then
    local trimmed = self.text:match("^%s*(.-)%s*$") or ""
    local CM = manager()
    if #trimmed > 0 and CM and CM.sendChat then
      CM.sendChat(trimmed)
      -- the box stays open for the reply: a conversation, not one line
      self.text = ""
      self:changed()
      pcall(Sound.play, self.game.data, "Press_AB")
    else
      self:cancel()
    end
  end
end

function CoopChatBox:update(dt)
  self.cursorTimer = self.cursorTimer + (dt or 0.016)
  -- one frame is enough for the opening key's text event to have come and gone
  if self.cursorTimer > 0.1 then self.swallowOpenKey = false end

  -- Fallback check for input if not delivered via keypressed
  local input = self.game and self.game.input
  if input then
    if input:wasPressed("b") and #self.text == 0 then
      self:cancel()
    elseif input:wasPressed("a") then
      -- a phone keyboard swiped away comes back on A
      setKeyboard(true)
    end
  end
end

function CoopChatBox:draw()
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(self.tx, self.ty, self.tw, self.th)

  love.graphics.setColor(0, 0, 0, 1)
  local top = (self.ty + 1) * 8
  Font.draw(isPhone() and "CHAT  A:KEYBOARD" or "CHAT ENTER/ESC", 8, top)

  -- the conversation, newest at the bottom
  local CM = manager()
  local lines = (CM and CM.chatLines) and CM.chatLines(18, LOG_ROWS) or {}
  for i, l in ipairs(lines) do
    Font.draw(l, 8, top + i * 8)
  end

  -- your line
  local cursor = (math.floor(self.cursorTimer * 3) % 2 == 0) and "_" or " "
  local text = self.text
  local y = top + (LOG_ROWS + 1) * 8
  -- the cartridge's own arrow; the Gen 2 font has no ">"
  Font.drawCode(0xED, 8, y)
  if #text <= 16 then
    Font.draw(text .. cursor, 16, y)
  else
    Font.draw(text:sub(1, 17), 16, y)
    Font.draw(text:sub(18) .. cursor, 8, y + 8)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return CoopChatBox
