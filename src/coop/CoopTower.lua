-- src/coop/CoopTower.lua
-- THE BATTLE TOWER IN MULTI (Crystal).  Each of the seven battles of a
-- challenge reaches the co-op offer like any trainer battle (the battle
-- room's script pushes it through OverworldState:pushBattle), and the
-- challenger can make it a CO-OP DOUBLE: the partner is asked wherever they
-- are -- the battle room is the challenger's alone -- and joins with up to
-- three Pokemon under the challenge's level cap, against the SAME opponent
-- (its name, class and three Pokemon travel with the invite rather than
-- being rolled again on the other side).
--
-- The challenge, its streak and its prizes are the challenger's.  The
-- partner's Pokemon come back from each battle as they went in: the tower
-- heals between battles and nobody blacks out there.

local CoopManager = require("src.coop.CoopManager")

local CoopTower = {}

function CoopTower.isTower(battle)
  return type(battle) == "table" and battle.battleTower == true
end

-- what the invite carries for a tower battle
function CoopTower.inviteInfo(game, battle)
  if not CoopTower.isTower(battle) then return nil end
  local BattleTower = require("src.world.BattleTower")
  local s = BattleTower.state(game.save)
  local opp = s and s.opponent
  if not opp then return nil end
  local party = {}
  for _, m in ipairs(opp.party or {}) do party[#party + 1] = CoopManager.wireMon(m) end
  return {
    opponent = { name = opp.name, class = opp.class, classKey = opp.classKey,
                 sprite = opp.sprite, female = opp.female, party = party },
    cap = BattleTower.maxLevel(s.group),
  }
end

-- the guest's Pokemon that may enter: healthy, not an egg, under the cap
function CoopTower.eligible(party, cap)
  local out = {}
  for _, m in ipairs(party or {}) do
    if not (m.isEgg or m.egg) and (tonumber(m.hp) or 0) > 0 and (not cap or (m.level or 0) <= cap) then
      out[#out + 1] = m
    end
  end
  return out
end

local function snapshot(mons)
  local out = {}
  for i, m in ipairs(mons or {}) do
    local moves = {}
    for j, mv in ipairs(m.moves or {}) do moves[j] = mv.pp end
    out[i] = { mon = m, hp = m.hp, status = m.status, pp = moves }
  end
  return out
end

local function restore(saved)
  require("src.coop.CoopLog").info("TOWER", "partner's team handed back (" .. #saved .. ")")
  for _, s in ipairs(saved) do
    s.mon.hp, s.mon.status = s.hp, s.status
    for j, mv in ipairs(s.mon.moves or {}) do
      if s.pp[j] ~= nil then mv.pp = s.pp[j] end
    end
  end
end

-- the guest's copy of the tower battle
function CoopTower.guestBattle(game, msg, chosenMons)
  local BattleState = require("src.battle.BattleState")
  local t = msg.tower
  local opp = {}
  for k, v in pairs(t.opponent or {}) do opp[k] = v end
  local party = {}
  for _, m in ipairs(opp.party or {}) do party[#party + 1] = CoopManager.wireMon(m) end
  opp.party = party
  local battle = BattleState.newBattleTowerTrainer(game, opp)
  -- a tower loss is no blackout, and the partner's team is lent, not spent
  battle.canLose = true
  local saved = snapshot(chosenMons)
  battle.onFinish = function()
    restore(saved)
    -- ...and again once the battle is off the stack: the end-of-battle rules
    -- of a co-op double run after this
    CoopTower.pending = { saved = saved, battle = battle }
  end
  return battle
end

CoopManager.onIdleTick("tower", function(dt, game)
  local p = CoopTower.pending
  if not p then return end
  for _, st in ipairs((game and game.stack and game.stack.states) or {}) do
    if st == p.battle then return end
  end
  CoopTower.pending = nil
  restore(p.saved)
end)

return CoopTower
