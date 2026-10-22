-- THE CO-OP EXTRAS (src/coop/Coop*.lua feature modules), one block each,
-- against a fake link that records what goes out.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local SaveData = require("src.core.SaveData")
local CoopManager = require("src.coop.CoopManager")
require("src.coop.CoopLog").enabled = false

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end,
                    isLinked = function() return true end, flush = function() end,
                    update = function() end, poll = function() return {} end }
CoopManager.connected = true
CoopManager.linkSerial = 1
CoopManager.partner.name = "TOBY"

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local pressed = {}
local save = SaveData.newGame()
save.player.name = "ME"
local game = { data = Data, save = save, stack = newStack(),
               input = { wasPressed = function(_, b) return pressed[b] end, isDown = function() return false end } }
package.loaded["src.core.Game"] = game

local function sentOf(kind)
  local out = {}
  for _, m in ipairs(sent) do if m.type == kind then out[#out + 1] = m end end
  return out
end

local function recv(msg) CoopManager.dispatch(nil, msg) end

-- two species the fixture data knows
local species = {}
for id in pairs(Data.pokemon) do species[#species + 1] = id end
table.sort(species)
local A, B, C = species[1], species[2], species[3]

-- ---------------------------------------------------------------------
-- POKéDEX: compare, and SHARE DEX
-- ---------------------------------------------------------------------

do
  local CoopDex = require("src.coop.CoopDex")
  save.pokedex = { seen = { [A] = true }, owned = { [A] = true } }
  sent = {}
  CoopManager.update(nil, 1 / 60)
  local whole = sentOf("coop_dex")
  T.check(#whole == 1 and whole[1].owned[1] == A, "the whole dex goes out once per link")
  CoopManager.update(nil, 1 / 60)
  T.check(#sentOf("coop_dex") == 1, "...and only once")

  save.pokedex.owned[B] = true
  CoopDex.checkTimer = CoopDex.CHECK_EVERY
  CoopManager.update(nil, 1 / 60)
  local adds = sentOf("coop_dex_add")
  T.check(#adds == 1 and adds[1].owned[1] == B, "a new catch goes out as it lands")

  recv({ type = "coop_dex", owned = { A, C }, seen = { A, C } })
  T.check(not save.pokedex.seen[C], "SHARE DEX off: the partner's catches stay theirs")
  local screen = CoopDex.open(game)
  local lists = screen:lists()
  T.check(#lists[1] == 1 and lists[1][1] == C, "the screen lists what only the partner has")
  T.check(#lists[2] == 1 and lists[2][1] == B, "...and what only you have")
  game.stack:pop()

  sent = {}
  CoopManager.setRule("shareDex", true)
  T.check(#sentOf("coop_rules") == 1, "SHARE DEX is a shared rule")
  T.check(#sentOf("coop_dex_req") == 1, "switching it on asks for the partner's dex")
  recv({ type = "coop_dex", owned = { A, C }, seen = { A, C } })
  T.check(save.pokedex.seen[C] and not save.pokedex.owned[C], "SHARE DEX on: their catch is SEEN, not owned")
  save.pokedex.seen[C] = nil
  recv({ type = "coop_dex_add", owned = { C } })
  T.check(save.pokedex.seen[C], "...and so is each new one")
  CoopManager.setRule("shareDex", false)

  CoopManager.linkSerial = 2
  sent = {}
  CoopManager.update(nil, 1 / 60)
  T.check(#sentOf("coop_dex") == 1 and CoopDex.partner == nil, "a new link starts over")
end

-- ---------------------------------------------------------------------
-- RECONNECT: the save remembers the link and picks it back up
-- ---------------------------------------------------------------------

do
  local CoopRejoin = require("src.coop.CoopRejoin")
  CoopManager.isHost = false
  CoopManager.net.address, CoopManager.net.port = "10.147.17.5:7777", 7777
  CoopManager.linkSerial = 3
  CoopManager.update(nil, 1 / 60)
  local link = save.coopLink
  T.check(link and link.role == "guest" and link.ip == "10.147.17.5" and link.partner == "TOBY",
    "a link is written into the save")

  local join, idleFn = CoopManager.join, CoopManager.overworldIdle
  local dials = 0
  CoopManager.join = function() dials = dials + 1 return true end
  CoopManager.overworldIdle = function() return true end
  CoopManager.connected = false
  CoopManager.net.closed = true
  local ow = { map = { id = "ROUTE_29" } }
  for _ = 1, 60 do CoopManager.update(ow, 1 / 60) end
  T.check(dials == 0, "not on the first second back on the map")
  for _ = 1, 120 do CoopManager.update(ow, 1 / 60) end
  T.check(dials == 1, "the guest dials the host once settled")
  for _ = 1, 40 do CoopManager.update(ow, 0.25) end
  T.check(dials == 1, "...and waits between tries")
  for _ = 1, 50 do CoopManager.update(ow, 0.25) end
  T.check(dials == 2, "...then tries again")
  CoopRejoin.stop(game)
  for _ = 1, 200 do CoopManager.update(ow, 0.25) end
  T.check(dials == 2, "DISCONNECT stops the tries")
  local opts = package.loaded["pkmultiplayer.options"]
  package.loaded["pkmultiplayer.options"] = { on = function() return false end }
  T.check(not CoopRejoin.enabled(), "AUTO RECONNECT can be switched off")
  package.loaded["pkmultiplayer.options"] = opts
  CoopManager.join, CoopManager.overworldIdle = join, idleFn
  CoopManager.connected = true
  CoopManager.net.closed = nil
end

T.finish("co-op extras")
