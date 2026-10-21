-- CO-OP DOUBLES: SWITCHING, AND FOES THAT THINK.
--
-- The two-copy harness of coop_turn_rules.lua, asking about the switch rule
-- and the foes' doubles AI:
--   * a switch goes before every move, on both copies, and each player can
--     only send in one of their own three;
--   * both players switching in the same turn, and the copies still agree;
--   * a Pokemon held by a foe's WRAP cannot be recalled (Gen 2 / HGSS);
--   * the foes' AI takes the KO it can see, does not waste a status move on
--     a Pokemon that already has one, and two foes do not both pile onto a
--     target the first one is already finishing.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
require("src.battle.TypeChart").load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")
local CoopBattle = require("src.coop.CoopBattle")
local CoopManager = require("src.coop.CoopManager")
local DoublesAI = require("src.battle.DoublesAI")
local Json = require("src.link.Json")
require("src.coop.CoopLog").enabled = false
CoopBattle.AUTO_REPLACE = true

-- moves the fixture set does not carry
Data.moves.FIX_HYPNO = { id = "FIX_HYPNO", index = 90, name = "FIX HYPNO", type = "PSYCHIC",
                         power = 0, accuracy = 60, pp = 20, effect = "SLEEP_EFFECT" }
Data.moves.FIX_SPLASHY = { id = "FIX_SPLASHY", index = 91, name = "FIX SPLASHY", type = "NORMAL",
                           power = 0, accuracy = 100, pp = 40, effect = "SPLASH_EFFECT" }
Data.moves.FIX_SLAM = { id = "FIX_SLAM", index = 92, name = "FIX SLAM", type = "NORMAL",
                        power = 120, accuracy = 100, pp = 10, effect = "NO_ADDITIONAL_EFFECT" }

local P = BattleState.POS

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local function newGame(name, species, level)
  local save = SaveData.newGame()
  save.player.name = name
  save.party = {}
  for i, sp in ipairs(species) do
    save.party[i] = Pokemon.new(Data, sp, level, function(a) return a end)
  end
  return { data = Data, save = save, stack = newStack(),
           input = { wasPressed = function() return false end, isDown = function() return false end } }
end

local function drain(b)
  for _ = 1, 20000 do
    if b.coop and b.coop.localReady then return end
    local top = b.game.stack:top()
    if top ~= b and top and top.update then
      top:update(1 / 60)
    elseif not b:updateQueue() then
      return (b.afterQueue == "finish" or b.result) and "done" or nil
    end
  end
  error("battle queue never drained")
end

local function pickMove(b)
  local me = b:battlerAt(P.PLAYER_LEFT)
  if not me then return nil end
  local mv = me.curMoves[1]
  local foe = b:battlerAt(P.OPPONENT_LEFT)
  mv.targetPosition = (foe and foe.mon.hp > 0) and P.OPPONENT_LEFT or P.OPPONENT_RIGHT
  return mv
end

local function setup(seed, level, hostSpecies, guestSpecies, record)
  local hostGame = newGame("HOST", hostSpecies, level)
  local guestGame = newGame("GUEST", guestSpecies, level)
  local bus = { host = {}, guest = {} }
  local sender = "host"
  CoopManager.connected = true
  CoopManager.net = { send = function(_, m)
                        table.insert(bus[sender == "host" and "guest" or "host"], Json.decode(Json.encode(m)))
                      end,
                      isLinked = function() return true end, flush = function() end }
  CoopManager.isConnected = function() return true end
  local hostWire, guestWire = {}, {}
  for i, m in ipairs(hostGame.save.party) do hostWire[i] = CoopManager.wireMon(m) end
  for i, m in ipairs(guestGame.save.party) do guestWire[i] = CoopManager.wireMon(m) end
  local hb = BattleState.newTrainer(hostGame, "OPP_FIX_YOUNGSTER", 1)
  hostGame.stack:push(hb)
  if record then record("host", hb) end
  CoopBattle.initBattle(hb, hostGame.save.party, guestWire, { name = "GUEST" }, seed, "SWITCH" .. seed)
  local gb = BattleState.newTrainer(guestGame, "OPP_FIX_YOUNGSTER", 1)
  gb.isCoopGuest = true
  guestGame.stack:push(gb)
  if record then record("guest", gb) end
  CoopBattle.initBattle(gb, guestGame.save.party, hostWire, { name = "HOST" }, seed, "SWITCH" .. seed)
  local function deliver(to)
    local q = bus[to]
    bus[to] = {}
    CoopBattle.currentBattle = (to == "host") and hb or gb
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m) end
    end
  end
  local function turn(hostAction, guestAction)
    sender = "host"; CoopBattle.currentBattle = hb
    local ha = hostAction and hostAction(hb) or pickMove(hb)
    if ha then CoopBattle.onLocalActionSelected(hb, ha) else CoopBattle.onSpectatorTurn(hb) end
    sender = "guest"; CoopBattle.currentBattle = gb
    local ga = guestAction and guestAction(gb) or pickMove(gb)
    if ga then CoopBattle.onLocalActionSelected(gb, ga) else CoopBattle.onSpectatorTurn(gb) end
    deliver("guest"); deliver("host")
    local r1, r2 = drain(hb), drain(gb)
    return r1 == "done" or r2 == "done" or hb.result or gb.result
  end
  drain(hb); drain(gb)
  return hb, gb, turn
end

local function species(b, pos)
  local x = b:battlerAt(pos)
  return x and x.mon and x.mon.species
end

-- the same four Pokemon on both copies, each player's own on their LEFT
local function agree(hb, gb)
  return species(hb, P.PLAYER_LEFT) == species(gb, P.PLAYER_RIGHT)
     and species(hb, P.PLAYER_RIGHT) == species(gb, P.PLAYER_LEFT)
     and species(hb, P.OPPONENT_LEFT) == species(gb, P.OPPONENT_LEFT)
     and species(hb, P.OPPONENT_RIGHT) == species(gb, P.OPPONENT_RIGHT)
end

local function switchTo(i)
  return function(b) return { special = "playerSwitch", mon = b.coopChosenMons[i] } end
end

-- ---------------------------------------------------------------------
-- switching
-- ---------------------------------------------------------------------

do
  local log = { host = {}, guest = {} }
  local function record(who, b)
    local exec = b.executeAction
    b.executeAction = function(self, user, target, action)
      if user and action then
        log[who][#log[who] + 1] = action.special == "playerSwitch" and "switch" or (action.id and "move") or "other"
      end
      return exec(self, user, target, action)
    end
  end
  local hb, gb, turn = setup(5151, 20, { "FIXMON_A", "FIXMON_B", "FIXMON_C" },
                             { "FIXMON_C", "FIXMON_A", "FIXMON_B" }, record)
  T.check(agree(hb, gb), "both copies open with the same four Pokemon")

  -- turn 1: the host switches to its second, the guest attacks
  turn(switchTo(2))
  T.check(species(hb, P.PLAYER_LEFT) == "FIXMON_B", "the host's own switch lands on the host's copy")
  T.check(species(gb, P.PLAYER_RIGHT) == "FIXMON_B", "...and on the guest's copy, in the partner slot")
  T.check(agree(hb, gb), "the copies agree after the host's switch")
  for _, who in ipairs({ "host", "guest" }) do
    T.check(log[who][1] == "switch", who .. "'s copy: the switch runs before every move")
  end

  -- turn 2: both switch at once
  log.host, log.guest = {}, {}
  turn(switchTo(3), switchTo(3))
  T.check(species(hb, P.PLAYER_LEFT) == "FIXMON_C" and species(hb, P.PLAYER_RIGHT) == "FIXMON_B",
          "both switching in one turn: each brings in their own third Pokemon")
  T.check(agree(hb, gb), "the copies agree after a double switch")
  for _, who in ipairs({ "host", "guest" }) do
    T.check(log[who][1] == "switch" and log[who][2] == "switch",
            who .. "'s copy: both switches come before the foes' moves")
  end

  -- the party a player picks from is their own three, never the partner's
  local own = {}
  for _, m in ipairs(hb.coopChosenMons) do own[m] = true end
  local leaked = false
  for _, m in ipairs(hb.ally.party or {}) do if own[m] then leaked = true end end
  T.check(not leaked, "the partner's Pokemon are not in the host's switch list")

  -- a fainted Pokemon cannot be sent in: the wire answer for it is refused
  local fainted = gb.ally.party[1]
  local savedHp = fainted.hp
  fainted.hp = 0
  local decoded = CoopBattle.decodeAction(gb, { kind = "switch", index = 1, species = fainted.species })
  T.check(decoded and decoded.mon == fainted,
          "a switch to a fainted Pokemon stays a no-op, the same one the partner's copy runs")
  local out = gb:battlerAt(P.PLAYER_RIGHT)
  local again = CoopBattle.decodeAction(gb, { kind = "switch", index = 99, species = out.mon.species })
  T.check(again == nil or again.mon ~= out.mon, "the species fallback never picks the Pokemon already out")
  fainted.hp = savedHp
end

-- ---------------------------------------------------------------------
-- WRAP holds you: "can't be recalled!"
-- ---------------------------------------------------------------------

do
  local hb, gb = setup(6262, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local me = hb:battlerAt(P.PLAYER_LEFT)
  T.check(hb:canRecall(me), "a free Pokemon can be recalled")
  local foe = hb:battlerAt(P.OPPONENT_LEFT)
  foe.trappingTurns = 2
  T.check(not hb:canRecall(me), "a Pokemon held by a foe's WRAP cannot be recalled")
  foe.trappingTurns = nil
end

-- ---------------------------------------------------------------------
-- MEAN LOOK holds you while its user stays out
-- ---------------------------------------------------------------------

do
  local MoveEffects = require("src.battle.MoveEffects")
  local hb = setup(6363, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local me = hb:battlerAt(P.PLAYER_LEFT)
  local foe = hb:battlerAt(P.OPPONENT_LEFT)
  local msgs = MoveEffects.primary.MEAN_LOOK_EFFECT(hb, foe, me)
  T.check(msgs and tostring(msgs[1]):find("run away"), "MEAN LOOK pins the Pokemon in")
  T.check(not hb:canRecall(me), "a Pokemon under MEAN LOOK cannot be recalled")
  msgs = MoveEffects.primary.MEAN_LOOK_EFFECT(hb, foe, me)
  T.check(tostring(msgs[1]):find("failed"), "a second MEAN LOOK on a held Pokemon fails")
  -- the holder leaves the field: a new battler stands in its slot
  local stand = {}
  for k, v in pairs(foe) do stand[k] = v end
  stand.trapped, stand.meanLookBy = nil, nil
  hb:placeBattler(P.OPPONENT_LEFT, stand)
  T.check(hb:canRecall(me), "the hold ends once the Pokemon that used MEAN LOOK has left")
  hb:placeBattler(P.OPPONENT_LEFT, foe)
  T.check(not hb:canRecall(me), "...and holds again while it is back out")
  foe.mon.hp = 0
  T.check(hb:canRecall(me), "a fainted holder lets go")
  foe.mon.hp = 10

  -- the foe's AI does not switch out of a hold either
  local TrainerAI = require("src.battle.TrainerAI")
  local mine = hb:battlerAt(P.PLAYER_LEFT)
  MoveEffects.primary.MEAN_LOOK_EFFECT(hb, mine, hb.enemy)
  T.check(TrainerAI.switchAction(hb) == nil, "a trainer cannot switch a held Pokemon out")
end

-- and from a wild battle there is no running
do
  local game = newGame("SOLO", { "FIXMON_A" }, 20)
  local b = BattleState.newWild(game, "FIXMON_B", 5)
  game.stack:push(b)
  drain(b)
  b.rng = function(a) return a end   -- every run roll would succeed
  local MoveEffects = require("src.battle.MoveEffects")
  MoveEffects.primary.MEAN_LOOK_EFFECT(b, b.enemy, b.player)
  b:tryRun()
  T.check(b.result ~= "run", "MEAN LOOK: a held Pokemon cannot run from a wild battle")
end

-- ---------------------------------------------------------------------
-- the foes think
-- ---------------------------------------------------------------------

local function foeMoves(b, pos, ids)
  local f = b:battlerAt(pos)
  f.curMoves = {}
  for i, id in ipairs(ids) do f.curMoves[i] = { id = id, pp = 10 } end
  return f
end

-- takes the KO it can see
do
  local hb = setup(7373, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local foe = foeMoves(hb, P.OPPONENT_LEFT, { "FIX_TACKLE", "FIX_SPLASHY" })
  local weak = hb:battlerAt(P.PLAYER_RIGHT)
  weak.mon.hp = 2
  local move, target = DoublesAI.choose(hb, foe, foe.curMoves)
  T.check(move and move.id == "FIX_TACKLE", "the foe attacks instead of splashing")
  T.check(target == weak, "the foe goes for the Pokemon it can knock out")
end

-- no sleep move on a Pokemon that is already asleep
do
  local hb = setup(8484, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local foe = foeMoves(hb, P.OPPONENT_LEFT, { "FIX_HYPNO" , "FIX_TACKLE" })
  local l, r = hb:battlerAt(P.PLAYER_LEFT), hb:battlerAt(P.PLAYER_RIGHT)
  l.mon.status, r.mon.status = "SLP", "SLP"
  local move = DoublesAI.choose(hb, foe, foe.curMoves)
  T.check(move and move.id == "FIX_TACKLE", "a sleep move is not wasted on two sleeping Pokemon")
  l.mon.status, r.mon.status = nil, nil
  local _, target = DoublesAI.choose(hb, foe, { foe.curMoves[1] })
  T.check(target ~= nil, "a status move still gets a target")
end

-- the second foe does not overkill what the first is finishing
do
  local hb = setup(9595, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local f1 = foeMoves(hb, P.OPPONENT_LEFT, { "FIX_SLAM" })
  local f2 = foeMoves(hb, P.OPPONENT_RIGHT, { "FIX_SLAM" })
  local l, r = hb:battlerAt(P.PLAYER_LEFT), hb:battlerAt(P.PLAYER_RIGHT)
  l.mon.hp = 3
  DoublesAI.beginTurn(hb)
  local _, t1 = DoublesAI.choose(hb, f1, f1.curMoves)
  local _, t2 = DoublesAI.choose(hb, f2, f2.curMoves)
  T.check(t1 == l, "the first foe takes the KO on the weakened Pokemon")
  T.check(t2 == r, "the second foe aims at the other Pokemon instead of piling on")
end

-- and both copies of a whole battle still agree with the AI choosing
do
  local hb, gb, turn = setup(1212, 12, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local same = true
  for _ = 1, 15 do
    if turn() then break end
    if not agree(hb, gb) then same = false end
    for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local a, c = hb:battlerAt(pos), gb:battlerAt(pos)
      if (a and a.mon.hp) ~= (c and c.mon.hp) then same = false end
    end
    local hl, gr = hb:battlerAt(P.PLAYER_LEFT), gb:battlerAt(P.PLAYER_RIGHT)
    if (hl and hl.mon.hp) ~= (gr and gr.mon.hp) then same = false end
  end
  T.check(same, "with the doubles AI choosing, both copies stay in lockstep")
end

T.finish("co-op doubles switching and foe AI")
