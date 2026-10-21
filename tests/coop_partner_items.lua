-- CO-OP: YOUR MEDICINE ON YOUR PARTNER'S POKEMON, AND A WARP WITH LIMITS.
--
--   * the free "heal both teams" button is gone, from the co-op menu and
--     from talking to your partner;
--   * USE ITEM sends one of your medicines to one of the partner's
--     Pokemon: their machine applies it, and it leaves YOUR bag only when it
--     worked; a stale pick (another species in that slot) or anything that is
--     not medicine is refused;
--   * WARP TO PARTNER recharges, and never lands in a gym, the League or on
--     the water.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local CoopManager = require("src.coop.CoopManager")
local CoopMenu = require("src.coop.CoopMenu")
require("src.coop.CoopLog").enabled = false

Data.items.POTION = { id = "POTION", index = 18, name = "POTION", price = 300 }
Data.items.ANTIDOTE = { id = "ANTIDOTE", index = 9, name = "ANTIDOTE", price = 100 }

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local function newGame(name)
  local save = SaveData.newGame()
  save.player.name = name
  save.party = { Pokemon.new(Data, "FIXMON_A", 20, function(a) return a end),
                 Pokemon.new(Data, "FIXMON_C", 20, function(a) return a end) }
  save.inventory = save.inventory or {}
  return { data = Data, save = save, stack = newStack(),
           input = { wasPressed = function() return false end, isDown = function() return false end } }
end

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end,
                    isLinked = function() return true end, flush = function() end }
CoopManager.connected = true
local function lastSent(kind)
  for i = #sent, 1, -1 do if sent[i].type == kind then return sent[i] end end
end

local function overworld(game, mapId)
  local ow = { game = game, isOverworld = true, map = { id = mapId }, player = { cellX = 3, cellY = 3 } }
  function ow:startWarpTo(map, x, y, f) self.warpedTo = { map = map, x = x, y = y } end
  return ow
end

-- ---------------------------------------------------------------------
-- no free heal button
-- ---------------------------------------------------------------------

do
  local game = newGame("ME")
  local menu = CoopMenu.new(game)
  local labels = {}
  for _, row in ipairs(menu:connectedRows(overworld(game, "ROUTE_29"))) do labels[#labels + 1] = row.label end
  local joined = table.concat(labels, "|")
  -- (PARTNER HEALS is the separate after-battle rule toggle, not a heal)
  T.check(not joined:find("HEAL BOTH", 1, true), "the co-op menu has no heal-both-teams row (" .. joined .. ")")
  T.check(joined:find("ITEM FOR PARTNER", 1, true) ~= nil, "the co-op menu offers ITEM FOR PARTNER")
  T.check(CoopManager.healBothParties == nil, "the heal-both-parties function is gone")

  local pushed
  game.stack.push = function(_, st) pushed = st end
  CoopManager.interact(game, overworld(game, "ROUTE_29"))
  local talk = {}
  for _, it in ipairs(pushed and pushed.items or {}) do talk[#talk + 1] = it.label end
  joined = table.concat(talk, "|")
  T.check(not joined:find("HEAL"), "talking to the partner offers no heal (" .. joined .. ")")
  T.check(joined:find("USE ITEM", 1, true) ~= nil, "talking to the partner offers USE ITEM")
end

-- ---------------------------------------------------------------------
-- the partner's machine applies the item
-- ---------------------------------------------------------------------

do
  local theirs = newGame("FRIEND")
  local ow = overworld(theirs, "ROUTE_29")
  local hurt = theirs.save.party[1]
  hurt.hp = 5

  sent = {}
  CoopManager.onPartyRequest(ow, { req = "R1" })
  local party = lastSent("coop_party")
  T.check(party and party.req == "R1" and #party.mons == 2, "the partner answers with their party")
  T.check(party.mons[1].hp == 5 and party.mons[1].slot == 1 and party.mons[1].species == "FIXMON_A",
          "each row carries slot, species and HP")

  sent = {}
  CoopManager.onItemUse(ow, { req = "U1", item = "POTION", slot = 1, species = "FIXMON_A", from = "ME" })
  local r = lastSent("coop_item_result")
  T.check(r and r.ok == true and hurt.hp == 25, "a POTION from the partner heals 20 HP on the owner's copy")

  sent = {}
  local full = theirs.save.party[2]
  local before = full.hp
  CoopManager.onItemUse(ow, { req = "U2", item = "POTION", slot = 2, species = "FIXMON_C" })
  r = lastSent("coop_item_result")
  T.check(r and r.ok == false and full.hp == before, "a POTION on a full-HP Pokemon does nothing and says so")

  sent = {}
  CoopManager.onItemUse(ow, { req = "U3", item = "POTION", slot = 1, species = "FIXMON_C" })
  r = lastSent("coop_item_result")
  T.check(r and r.refused and hurt.hp == 25, "a stale pick (another species in the slot) is refused")

  sent = {}
  CoopManager.onItemUse(ow, { req = "U4", item = "FIX_TM", slot = 1, species = "FIXMON_A" })
  r = lastSent("coop_item_result")
  T.check(r and r.refused, "only medicine crosses the wire; a TM is refused")

  hurt.status = "PSN"
  sent = {}
  CoopManager.onItemUse(ow, { req = "U5", item = "ANTIDOTE", slot = 1, species = "FIXMON_A" })
  r = lastSent("coop_item_result")
  T.check(r and r.ok and hurt.status == nil, "an ANTIDOTE cures the partner's poisoned Pokemon")
end

-- ---------------------------------------------------------------------
-- your bag pays only when it worked
-- ---------------------------------------------------------------------

do
  local mine = newGame("ME")
  local ow = overworld(mine, "ROUTE_29")
  local Bag = require("src.inventory.Bag")
  Bag.add(mine.save, "POTION", 2, Data)
  CoopManager.partner.map = "ROUTE_29"
  CoopManager.partner.lastSeen = 1e12
  CoopManager.partner.inBattle, CoopManager.partner.busy, CoopManager.partner.inDialogue = false, false, false
  local ids = CoopManager.medicineIds(mine)
  T.check(#ids == 1 and ids[1] == "POTION", "the item list is the medicine in your bag")

  CoopManager.itemRequest = nil
  sent = {}
  CoopManager.sendItemUse(mine, ow, "POTION", { slot = 1, species = "FIXMON_A" })
  local use = lastSent("coop_item_use")
  T.check(use and use.item == "POTION" and use.slot == 1, "the pick goes to the partner")
  T.check(mine.save.inventory.POTION == 2, "...and nothing leaves the bag before they answer")
  CoopManager.onItemResult(ow, { req = use.req, ok = false, messages = { "It won't have\nany effect." } })
  T.check(mine.save.inventory.POTION == 2, "an item that did nothing stays in your bag")

  sent = {}
  CoopManager.sendItemUse(mine, ow, "POTION", { slot = 1, species = "FIXMON_A" })
  use = lastSent("coop_item_use")
  CoopManager.onItemResult(ow, { req = use.req, ok = true, messages = { "Recovered!" } })
  T.check(mine.save.inventory.POTION == 1, "an item that worked is spent from YOUR bag")
  CoopManager.onItemResult(ow, { req = use.req, ok = true })
  T.check(mine.save.inventory.POTION == 1, "a repeated answer spends nothing more")
end

-- ---------------------------------------------------------------------
-- the warp recharges and stays out of gyms and water
-- ---------------------------------------------------------------------

do
  local mine = newGame("ME")
  local p = CoopManager.partner
  p.map, p.cx, p.cy, p.lastSeen = "VIOLET_CITY", 5, 6, 1e12
  p.inBattle, p.busy, p.inDialogue, p.surfing = false, false, false, false
  CoopManager.lastWarpAt = nil

  local ow = overworld(mine, "ROUTE_29")
  local ok, why = CoopManager.canWarpToPartner(ow)
  T.check(ok, "a fresh warp to an idle partner is allowed (" .. tostring(why) .. ")")
  T.check(CoopManager.warpToPartner(ow) and ow.warpedTo and ow.warpedTo.map == "VIOLET_CITY",
          "the warp lands on the partner")

  ow = overworld(mine, "ROUTE_29")
  ok, why = CoopManager.canWarpToPartner(ow)
  T.check(not ok and tostring(why):find("Warp ready in"), "a second warp waits for the recharge (" .. tostring(why) .. ")")
  T.check(not CoopManager.warpToPartner(ow) and ow.warpedTo == nil, "...and does not move you")

  CoopManager.lastWarpAt = nil
  p.map = "VIOLET_GYM"
  ok = CoopManager.canWarpToPartner(ow)
  T.check(not ok, "no warping into a gym")
  p.map = "VIOLET_CITY"
  p.surfing = true
  ok = CoopManager.canWarpToPartner(ow)
  T.check(not ok, "no warping onto a partner who is surfing")
  p.surfing = false
  p.inBattle = true
  ok = CoopManager.canWarpToPartner(ow)
  T.check(not ok, "no warping to a partner in a battle")
  p.inBattle = false
end

T.finish("co-op partner items and warp")
