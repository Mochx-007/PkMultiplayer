-- src/coop/CoopMenu.lua
-- In-game UI for creating, joining and managing the Co-op session.
-- Designed natively for Game Boy 4:3 (160x144, 20x18 tiles) with pure retro aesthetic.

local CoopManager = require("src.coop.CoopManager")
local CoopNet = require("src.coop.CoopNet")
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local CoopMenu = {}
CoopMenu.__index = CoopMenu
CoopMenu.isOpaque = true

local CURSOR = 0xED
local DOWN_ARROW = 0xEE
-- rows the linked menu shows at once (it scrolls past that)
local VISIBLE_ROWS = 9

-- The address being typed, as twelve digits (three per octet), so the
-- cursor can walk them one by one.  Starts from this machine's own address,
-- which on a ZeroTier network shares its first three octets with the host's.
local function ipDigits(ip)
  local octets = { (ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$") }
  if #octets ~= 4 then octets = { 192, 168, 1, 100 } end
  local text = ""
  for _, o in ipairs(octets) do
    text = text .. ("%03d"):format(math.min(255, tonumber(o) or 0))
  end
  local digits = {}
  for ch in text:gmatch("%d") do digits[#digits + 1] = tonumber(ch) end
  return digits
end

-- ...and back to "a.b.c.d", each octet capped at 255
local function digitsIP(digits)
  local text = table.concat(digits)
  local parts = {}
  for chunk in text:gmatch("%d%d%d") do
    parts[#parts + 1] = tostring(math.min(255, tonumber(chunk)))
  end
  return table.concat(parts, ".")
end

-- the digit under the cursor, turned like a dial
local function turnDigit(self, step)
  self.addr[self.addrPos] = (self.addr[self.addrPos] + step) % 10
end

-- the cursor, kept on the twelve digits
local function moveCursor(self, step)
  local pos = self.addrPos + step
  if pos >= 1 and pos <= #self.addr then self.addrPos = pos end
end

function CoopMenu.new(game)
  local self = setmetatable({}, CoopMenu)
  self.game = game
  self.stage = "main"
  self.index = 1
  self.addr = ipDigits(CoopNet.zeroTierIP() or CoopNet.lanIP())
  self.addrPos = 12
  self.port = CoopNet.DEFAULT_PORT
  return self
end

local function findOverworld(game)
  if not game then return nil end
  if game.overworld and game.overworld.isOverworld then return game.overworld end
  local stack = game.stack
  local states = stack and stack.states
  if states then
    for i = #states, 1, -1 do
      if states[i] and states[i].isOverworld then return states[i] end
    end
  end
  return nil
end

function CoopMenu:close()
  self.game.stack:pop()
end

local function onOff(v) return v and "ON" or "OFF" end

-- the warp row shows its cooldown while it recharges
local function warpLabel()
  if CoopManager.warpAsking and CoopManager.warpAsking() then return "WARP (ASKING)" end
  local left = math.ceil(CoopManager.warpCooldownLeft())
  if left <= 0 then return "WARP TO PARTNER" end
  return string.format("WARP (%d:%02d)", math.floor(left / 60), left % 60)
end

-- The linked menu, as data: what it says and what A does.  The rules rows
-- are shared -- toggling one changes it for both players (coop_rules).
function CoopMenu:connectedRows(ow)
  local menu = self
  return {
    -- the way into the chat on a phone, which has no T key
    { label = "CHAT  (KEY T)", run = function()
      menu:close()
      CoopManager.openChat(menu.game, ow)
    end },
    { label = warpLabel(), run = function()
      menu:close()
      if ow then CoopManager.warpToPartner(ow) end
    end },
    { label = "ITEM FOR PARTNER", run = function()
      menu:close()
      if ow then CoopManager.useItemOnPartner(menu.game, ow) end
    end },
    { label = "POKéDEX", run = function()
      require("src.coop.CoopDex").open(menu.game)
    end },
    { label = "SHARE DEX " .. onOff(CoopManager.shareDex), run = function()
      CoopManager.setRule("shareDex", not CoopManager.shareDex)
    end },
    { label = "STORY SYNC " .. onOff(CoopManager.storySync), run = function()
      CoopManager.setRule("storySync", not CoopManager.storySync)
    end },
    { label = "PARTNER HEAL " .. onOff(CoopManager.partnerHeals), run = function()
      CoopManager.setRule("partnerHeals", not CoopManager.partnerHeals)
    end },
    { label = "TRADE", run = function()
      menu:close()
      require("src.coop.CoopLink").invite(menu.game, "trade")
    end },
    { label = "BATTLE P1 VS P2", run = function()
      menu:close()
      require("src.coop.CoopLink").invite(menu.game, "battle")
    end },
    { label = "EMOTE  (KEY Y)", run = function()
      menu:close()
      require("src.coop.CoopEmotes").openPicker(menu.game)
    end },
    { label = "DISCONNECT", run = function()
      require("src.coop.CoopRejoin").stop(menu.game)
      CoopManager.disconnect()
      menu.index = 1
    end },
  }
end

-- The offline menu, the same way.  RECONNECT leads it when the save
-- remembers a link (CoopRejoin): the host listens again, the guest dials.
function CoopMenu:offlineRows()
  local menu = self
  local rows = {}
  local link = self.game.save and self.game.save.coopLink
  if link then
    local who = tostring(link.partner or "PARTNER"):sub(1, 6)
    rows[#rows + 1] = { label = "RECONNECT " .. who, run = function()
      menu.errorMsg = nil
      if require("src.coop.CoopRejoin").try(menu.game, true) then
        menu.stage = (link.role == "host") and "hosting" or "joining"
      else
        menu.errorMsg = (CoopManager.net and CoopManager.net.error) or "FAILED"
      end
    end }
  end
  rows[#rows + 1] = { label = "HOST", run = function()
    menu.errorMsg = nil
    if CoopManager.host(menu.port) then
      menu.stage = "hosting"
    else
      menu.errorMsg = (CoopManager.net and CoopManager.net.error) or "FAILED TO HOST"
    end
  end }
  rows[#rows + 1] = { label = "JOIN", run = function() menu.stage = "addrEntry" end }
  rows[#rows + 1] = { label = "STORY SYNC " .. onOff(CoopManager.storySync), run = function()
    CoopManager.storySync = not CoopManager.storySync
  end }
  rows[#rows + 1] = { label = "EMOTE", run = function()
    menu.stage = "emotes"
    menu.index = 1
  end }
  rows[#rows + 1] = { label = "EXIT", run = function() menu:close() end }
  return rows
end

-- where an offline row sits (RECONNECT pushes the others down)
function CoopMenu:offlineIndex(label)
  for i, row in ipairs(self:offlineRows()) do
    if row.label == label then return i end
  end
  return 1
end

function CoopMenu:update(dt)
  local input = self.game.input
  local ow = findOverworld(self.game)
  -- the transport is pumped by CoopManager.update from Game:update; pumping
  -- it here as well split the inbox between two readers

  if self.stage == "main" then
    local isConn = CoopManager.isConnected()
    local rows = isConn and self:connectedRows(ow) or self:offlineRows()
    local maxItems = #rows
    if self.index > maxItems then self.index = 1 end

    if input:wasPressed("down") then
      self.index = (self.index % maxItems) + 1
    elseif input:wasPressed("up") then
      self.index = ((self.index - 2) % maxItems) + 1
    elseif input:wasPressed("b") then
      self:close()
    elseif input:wasPressed("a") then
      local row = rows[self.index]
      if row and row.run then row.run() end
    end

  elseif self.stage == "hosting" then
    if input:wasPressed("b") then
      CoopManager.disconnect()
      self.stage = "main"
      self.index = 1
    end
    if CoopManager.isConnected() then
      self.stage = "main"
      self.index = 1
    end

  elseif self.stage == "addrEntry" then
    if input:wasPressed("b") then
      self.stage = "main"
      self.index = self:offlineIndex("JOIN")
    elseif input:wasPressed("up") then
      turnDigit(self, 1)
    elseif input:wasPressed("down") then
      turnDigit(self, -1)
    elseif input:wasPressed("left") then
      moveCursor(self, -1)
    elseif input:wasPressed("right") then
      moveCursor(self, 1)
    elseif input:wasPressed("a") then
      local targetIP = digitsIP(self.addr)
      self.errorMsg = nil
      if CoopManager.join(targetIP, self.port) then
        self.stage = "joining"
      else
        self.errorMsg = (CoopManager.net and CoopManager.net.error) or "FAILED TO CONNECT"
      end
    end

  elseif self.stage == "joining" then
    if input:wasPressed("b") then
      CoopManager.disconnect()
      self.stage = "main"
      self.index = self:offlineIndex("JOIN")
    elseif CoopManager.isConnected() then
      self.stage = "main"
      self.index = 1
    elseif not CoopManager.net or CoopManager.net.closed then
      self.errorMsg = (CoopManager.net and CoopManager.net.error) or "HOST NOT FOUND"
      self.stage = "addrEntry"
    end

  elseif self.stage == "emotes" then
    local emoteList = { "heart", "exclaim", "question", "music", "star" }
    if input:wasPressed("down") then
      self.index = (self.index % #emoteList) + 1
    elseif input:wasPressed("up") then
      self.index = ((self.index - 2) % #emoteList) + 1
    elseif input:wasPressed("b") then
      self.stage = "main"
      self.index = 1
    elseif input:wasPressed("a") then
      local picked = emoteList[self.index]
      CoopManager.sendEmote(picked)
      pcall(function()
        local Sound = require("src.core.Sound")
        Sound.play(self.game.data, "Collision")
      end)
      self:close()
    end
  end
end

-- Clear screen to Game Boy background
local function clearGB()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
end

local function fit(text, n)
  text = tostring(text or "")
  if #text > n then return text:sub(1, n) end
  return text
end

-- All lines fit the 18 columns inside a full-width box (x 8..152).
function CoopMenu:draw()
  clearGB()
  local isConn = CoopManager.isConnected()
  local partner = CoopManager.partner

  if self.stage == "main" then
    Font.drawBox(0, 0, 20, 5)
    local rows
    if not isConn then
      Font.draw("CO-OP LINK", 8, 8)
      Font.draw("YOUR IP:", 8, 16)
      Font.draw(fit(CoopNet.zeroTierIP() or CoopNet.lanIP(), 18), 8, 24)
      rows = {}
      for i, row in ipairs(self:offlineRows()) do rows[i] = row.label end
    else
      Font.draw("LINK: " .. fit(partner.name or "PARTNER", 8), 8, 8)
      Font.draw("AREA:", 8, 16)
      -- the round trip, right-aligned on the AREA line
      local ms = CoopManager.net and tonumber(CoopManager.net.rttMs)
      if ms then
        local text = ("%dMS"):format(math.min(9999, ms))
        Font.draw(text, 152 - #text * 8, 16)
      end
      Font.draw(fit(CoopManager.mapLabel and CoopManager.mapLabel(partner.map) or partner.map, 18), 8, 24)
      rows = {}
      for i, row in ipairs(self:connectedRows(findOverworld(self.game))) do rows[i] = row.label end
    end
    Font.drawBox(0, 5, 20, 13)
    -- tighter rows once linked: the list is longer than the five offline ones.
    -- Nine rows at 9px fill the box exactly, from under its top border (48)
    -- to the footer (128); B closes the menu, so there is no RESUME row.
    -- Labels are 16 characters at most: x = 24 to the border at 152.
    -- More than nine rows scroll, a window of nine kept around the cursor,
    -- with the down arrow while more rows wait below (the font has no up
    -- arrow; the cursor shows the way back).
    local pitch = (#rows > 8) and 9 or ((#rows > 6) and 10 or 12)
    local top = 48
    local first = 1
    if #rows > VISIBLE_ROWS then
      self.scroll = self.scroll or 1
      if self.index < self.scroll then self.scroll = self.index end
      if self.index > self.scroll + VISIBLE_ROWS - 1 then self.scroll = self.index - VISIBLE_ROWS + 1 end
      first = self.scroll
    end
    for i = first, math.min(#rows, first + VISIBLE_ROWS - 1) do
      Font.draw(rows[i], 24, top + (i - first) * pitch)
    end
    Font.drawCode(CURSOR, 12, top + (self.index - first) * pitch)
    if first + VISIBLE_ROWS - 1 < #rows then
      Font.drawCode(DOWN_ARROW, 144, top + (VISIBLE_ROWS - 1) * pitch)
    end
    Font.draw("A:OK  B:BACK", 8, 128)

  elseif self.stage == "hosting" then
    Font.drawBox(0, 0, 20, 7)
    Font.draw("HOSTING SESSION", 8, 8)
    Font.draw("PORT: " .. self.port, 8, 24)
    Font.draw("IP:", 8, 32)
    Font.draw(fit(CoopNet.zeroTierIP() or CoopNet.lanIP(), 18), 8, 40)
    Font.drawBox(0, 7, 20, 11)
    Font.draw("TELL YOUR FRIEND", 8, 64)
    Font.draw("TO JOIN THIS IP.", 8, 72)
    local dots = string.rep(".", math.floor((love.timer and love.timer.getTime() or 0) * 2) % 4)
    Font.draw("WAITING" .. dots, 8, 96)
    Font.draw("B:CANCEL", 8, 128)

  elseif self.stage == "addrEntry" then
    Font.drawBox(0, 0, 20, 4)
    Font.draw("ENTER HOST IP", 8, 12)
    Font.drawBox(0, 4, 20, 14)
    for i = 1, 12 do
      local octet = math.floor((i - 1) / 3)
      local x = 16 + (i - 1) * 9 + octet * 6
      Font.draw(tostring(self.addr[i]), x, 52)
      if i == self.addrPos then
        Font.drawCode(DOWN_ARROW, x, 60)
      end
    end
    for octet = 1, 3 do
      Font.draw(".", 16 + octet * 33 - 6, 52)
    end
    Font.draw("PORT: " .. self.port, 8, 80)
    Font.draw("D-PAD: EDIT IP", 8, 96)
    Font.draw("A:JOIN  B:BACK", 8, 128)

  elseif self.stage == "joining" then
    Font.drawBox(0, 0, 20, 6)
    local dots = string.rep(".", math.floor((love.timer and love.timer.getTime() or 0) * 2) % 4)
    Font.draw("CONNECTING" .. dots, 8, 16)
    Font.drawBox(0, 6, 20, 12)
    Font.draw("WAITING FOR THE", 8, 64)
    Font.draw("HOST TO ANSWER", 8, 72)
    Font.draw("B:CANCEL", 8, 128)

  elseif self.stage == "emotes" then
    -- Header pill badge
    local hx, hy, hw, hh = 28, 6, 104, 15
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", hx + 1, hy, hw - 2, 1)
    love.graphics.rectangle("fill", hx + 1, hy + hh - 1, hw - 2, 1)
    love.graphics.rectangle("fill", hx, hy + 1, 1, hh - 2)
    love.graphics.rectangle("fill", hx + hw - 1, hy + 1, 1, hh - 2)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", hx + 1, hy + 1, hw - 2, hh - 2)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw("SELECT EMOTE", hx + 10, hy + 4)

    local items = {
      { id = "heart", sym = "<3", name = "HEART" },
      { id = "exclaim", sym = "!", name = "EXCLAIM" },
      { id = "question", sym = "?", name = "QUESTION" },
      { id = "music", sym = "#", name = "MUSIC" },
      { id = "star", sym = "*", name = "STAR" },
    }

    local startY = 26
    for i, it in ipairs(items) do
      local y = startY + (i - 1) * 18
      local bx, by, bw, bh = 18, y, 124, 16
      local isSel = (i == self.index)

      -- Outer rounded black border
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", bx + 1, by, bw - 2, 1)
      love.graphics.rectangle("fill", bx + 1, by + bh - 1, bw - 2, 1)
      love.graphics.rectangle("fill", bx, by + 1, 1, bh - 2)
      love.graphics.rectangle("fill", bx + bw - 1, by + 1, 1, bh - 2)

      -- White background fill inside
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", bx + 1, by + 1, bw - 2, bh - 2)

      if isSel then
        -- Selected: inner framed border + cursor
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", bx + 3, by + 2, bw - 6, 1)
        love.graphics.rectangle("fill", bx + 3, by + bh - 3, bw - 6, 1)
        love.graphics.rectangle("fill", bx + 2, by + 3, 1, bh - 6)
        love.graphics.rectangle("fill", bx + bw - 3, by + 3, 1, bh - 6)

        Font.drawCode(CURSOR, bx + 5, by + 4)
        Font.draw(it.sym, bx + 18, by + 4)
        Font.draw(it.name, bx + 42, by + 4)
      else
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw(it.sym, bx + 18, by + 4)
        Font.draw(it.name, bx + 42, by + 4)
      end
    end

    -- Footer pill badge
    local fx, fy, fw, fh = 14, 122, 132, 15
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", fx + 1, fy, fw - 2, 1)
    love.graphics.rectangle("fill", fx + 1, fy + fh - 1, fw - 2, 1)
    love.graphics.rectangle("fill", fx, fy + 1, 1, fh - 2)
    love.graphics.rectangle("fill", fx + fw - 1, fy + 1, 1, fh - 2)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", fx + 1, fy + 1, fw - 2, fh - 2)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw("A: SEND     B: BACK", fx + 10, fy + 4)
  end

  if self.errorMsg and (self.stage == "main" or self.stage == "addrEntry") then
    love.graphics.setColor(0.8, 0.1, 0.1, 1)
    Font.draw(fit(self.errorMsg, 18), 8, 116)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return CoopMenu
