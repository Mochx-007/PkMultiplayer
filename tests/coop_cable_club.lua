-- CO-OP CABLE CLUB: the game's own trade room and link battle, opened
-- between the two co-op players through the co-op link (src/coop/CoopLink)
-- instead of a second socket.  Two real LinkStates, one per player, joined
-- by their tunnels: both must reach the trade room, and both must start the
-- link battle.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local CoopLink = require("src.coop.CoopLink")
local CoopManager = require("src.coop.CoopManager")
require("src.coop.CoopLog").enabled = false
CoopManager.isConnected = function() return true end

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) if x.enter then x:enter() end end
  function s:pop() local x = table.remove(self.states) if x and x.exit then x:exit() end return x end
  function s:top() return self.states[#self.states] end
  return s
end
local function newGame(name)
  local save = SaveData.newGame()
  save.player.name = name
  save.party = { Pokemon.new(Data, "FIXMON_A", 20), Pokemon.new(Data, "FIXMON_B", 20) }
  local g = { data = Data, save = save, stack = newStack(),
              input = { pressed = {}, wasPressed = function(self, k) return self.pressed[k] end, isDown = function() return false end } }
  g.stack:push({ isOverworld = true })
  return g
end

for _, mode in ipairs({ "trade", "battle" }) do
  local A, B = newGame("TOBY"), newGame("MOCHX")
  -- B (the one asked) opens first, as on the network; its hello is buffered
  local sentByB = {}
  CoopManager.net = { send = function(_, m) table.insert(sentByB, m) end, flush = function() end }
  local lsB = CoopLink.openLinkState(B, mode, false)
  local tB = CoopLink.adapter
  local sentByA = {}
  CoopManager.net = { send = function(_, m) table.insert(sentByA, m) end, flush = function() end }
  CoopLink.adapter = nil -- (one process plays both machines: A has no tunnel yet)
  for _, m in ipairs(sentByB) do CoopLink.onLinkMessage(m) end
  sentByB = {}
  local lsA = CoopLink.openLinkState(A, mode, true)
  local tA = CoopLink.adapter
  -- from here each tunnel delivers into the other
  tA.send = function(self, m) table.insert(tB.inbox, m) end
  tB.send = function(self, m) table.insert(tA.inbox, m) end
  for _, m in ipairs(sentByA) do if m.payload then table.insert(tB.inbox, m.payload) end end
  local stagesA, stagesB = {}, {}
  for i = 1, 400 do
    if A.stack:top() == lsA then
      -- the asker answers the level-rule screen for a battle with A
      A.input.pressed = (lsA.stage == "battleOptions") and { a = true } or {}
      lsA:update(1 / 60)
    end
    if B.stack:top() == lsB then lsB:update(1 / 60) end
    stagesA[lsA.stage] = true; stagesB[lsB.stage] = true
    if mode == "trade" and lsA.stage == "trade" and lsB.stage == "trade" then break end
    if mode == "battle" and lsA.stage == "battleRunning" and lsB.stage == "battleRunning" then break end
  end
  if mode == "trade" then
    T.eq(lsA.stage, "trade", "asker reaches the trade room through the co-op tunnel")
    T.eq(lsB.stage, "trade", "partner reaches the trade room too")
    T.check(lsA.verdict == "full", "handshake verdict over the tunnel: " .. tostring(lsA.verdict))
  else
    T.eq(lsA.stage, "battleRunning", "asker's link battle starts")
    T.eq(lsB.stage, "battleRunning", "partner's link battle starts")
  end
  tA:close(); tB:close()
end
T.finish("co-op cable club tunnel")
