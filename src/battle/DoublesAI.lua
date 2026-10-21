-- THE FOES OF A CO-OP DOUBLE, THINKING ABOUT BOTH OF YOU.
--
-- Johto's trainers carry no AI flags this port runs, so in a double every
-- foe used to roll one of its moves at random and aim it at a coin flip --
-- a Hypnosis into a Pokemon already asleep, a Splash with a KO on the table,
-- both foes emptying everything into a Pokemon the first one had already
-- finished.  This is the HGSS-era doubles brain in miniature: every usable
-- (move, target) pair is scored and the best one is taken.
--
--   * damage is ESTIMATED -- the cartridge's formula on the live stats and
--     stages, a middle damage roll, no crit -- and never rolled, because the
--     shared RNG is drawn in the same order on both copies of the battle and
--     a draw spent here on one copy only would split them;
--   * a hit that knocks out is worth much more than the HP it takes;
--   * a status move is worth nothing on a Pokemon that already has one, or
--     whose type shrugs it off;
--   * the two foes share a plan for the turn (DoublesAI.beginTurn): the
--     second one sees what the first one is already dealing and does not
--     pile onto a Pokemon that is going down anyway;
--   * a spread move that also hits its own partner pays for that.
--
-- Only state both copies hold is read, foes are walked in foesOf's canonical
-- order (the host's Pokemon first on both copies), and a tie is the only
-- thing the RNG decides -- so both machines pick the same pair.

local Targeting = require("src.battle.Targeting")
local TypeChart = require("src.battle.TypeChart")
local Damage = require("src.battle.Damage")
local Stats = require("src.pokemon.Stats")

local DoublesAI = {}

local function alive(b)
  return b and b.mon and not b.fainted and not b.faintQueued and (b.mon.hp or 0) > 0
end

local function maxHp(b)
  local s = b.curStats or b.mon.stats or {}
  return math.max(1, s.hp or b.mon.maxHp or b.mon.hp or 1)
end

local function hpPct(b) return (b.mon.hp or 0) * 100 / maxHp(b) end

local function hasType(b, t)
  for _, x in ipairs(b.curTypes or {}) do if x == t then return true end end
  return false
end

local function eff(moveType, b)
  local ok, m = pcall(TypeChart.effectiveness, moveType, b.curTypes or {})
  return ok and tonumber(m) or 10
end

local function accuracy(def)
  local a = tonumber(def.accuracy) or 100
  if a <= 0 then return 1 end
  return math.min(100, a) / 100
end

local function stat(b, key)
  local s = b.curStats or b.mon.stats or {}
  local v = s[key]
  if v == nil and (key == "spatk" or key == "spdef") then v = s.special end
  return math.max(1, Stats.applyStage(v or 1, Damage.stageOf(b, key)))
end

local FIXED = { SONICBOOM = 20, DRAGON_RAGE = 40 }
local LEVEL_DAMAGE = { SEISMIC_TOSS = true, NIGHT_SHADE = true, PSYWAVE = true }
-- power 1 in the move record; the real number is worked out when it hits
local VARIABLE_POWER = {
  RETURN_EFFECT = 70, FRUSTRATION_EFFECT = 40, HIDDEN_POWER_EFFECT = 60,
  MAGNITUDE_EFFECT = 70, PRESENT_EFFECT = 40, REVERSAL_EFFECT = 60,
  BEAT_UP_EFFECT = 40,
}
local MULTI_HIT = { TWO_TO_FIVE_ATTACKS_EFFECT = 3, ATTACK_TWICE_EFFECT = 2, TWINEEDLE_EFFECT = 2 }
local TWO_TURN = { SOLARBEAM_EFFECT = true, FLY_EFFECT = true, CHARGE_EFFECT = true }

-- expected HP this move takes off `target`, before accuracy
local function estimate(battle, user, target, def, spread)
  local power = tonumber(def.power) or 0
  if power <= 0 then return 0 end
  local e = eff(def.type, target)
  if e == 0 then return 0 end
  local id = def.id
  if FIXED[id] then return FIXED[id] end
  if LEVEL_DAMAGE[id] then return user.mon.level or 1 end
  if def.effect == "SUPER_FANG_EFFECT" then return math.max(1, math.floor((target.mon.hp or 0) / 2)) end
  if def.effect == "OHKO_EFFECT" then
    if (user.mon.level or 0) < (target.mon.level or 0) then return 0 end
    return target.mon.hp or 0
  end
  if def.effect == "DREAM_EATER_EFFECT" and target.mon.status ~= "SLP" then return 0 end
  if power <= 1 then power = VARIABLE_POWER[def.effect] or 50 end
  local special = Damage.isSpecial(def.type)
  local atk = stat(user, special and "spatk" or "attack")
  local dfn = stat(target, special and "spdef" or "defense")
  local d = Damage.base(user.mon.level or 1, power, atk, dfn) + 2
  if hasType(user, def.type) then d = d * 1.5 end
  d = d * e / 10
  local side = battle.sides and battle.sides[target.isPlayer and 1 or 2]
  if side and ((special and side.lightScreen) or (not special and side.reflect)) then d = d * 2 / 3 end
  if spread then d = d * 3 / 4 end
  d = d * (MULTI_HIT[def.effect] or 1) * 236 / 255 -- the middle of the damage roll
  if def.effect == "FALSE_SWIPE_EFFECT" then d = math.min(d, (target.mon.hp or 1) - 1) end
  return math.max(1, math.floor(d))
end

-- what a hit of `dmg` is worth against `target`, given what is already
-- planned against it this turn
local function hitValue(plan, target, dmg)
  if dmg <= 0 then return 0 end
  local left = (target.mon.hp or 0) - (plan[target] or 0)
  local cap = maxHp(target)
  if left <= 0 then return dmg * 8 / cap end      -- it is going down anyway
  local v = math.min(dmg, left) * 100 / cap
  if dmg >= left then v = v + 60 end              -- the knockout
  return v
end

local function stageOf(b, s) return (b.stages and b.stages[s]) or 0 end

local STAT_DOWN = {
  ATTACK_DOWN_EFFECT = "attack", DEFENSE_DOWN_EFFECT = "defense", SPEED_DOWN_EFFECT = "speed",
  SP_ATK_DOWN_EFFECT = "spatk", SP_DEF_DOWN_EFFECT = "spdef", ACCURACY_DOWN_EFFECT = "accuracy",
  EVASION_DOWN_EFFECT = "evasion",
  ATTACK_DOWN2_EFFECT = "attack", DEFENSE_DOWN2_EFFECT = "defense", SPEED_DOWN2_EFFECT = "speed",
  SP_ATK_DOWN2_EFFECT = "spatk", SP_DEF_DOWN2_EFFECT = "spdef", ACCURACY_DOWN2_EFFECT = "accuracy",
  EVASION_DOWN2_EFFECT = "evasion",
}
local STAT_UP = {
  ATTACK_UP_EFFECT = "attack", DEFENSE_UP_EFFECT = "defense", SPEED_UP_EFFECT = "speed",
  SP_ATK_UP_EFFECT = "spatk", SP_DEF_UP_EFFECT = "spdef", EVASION_UP_EFFECT = "evasion",
  ATTACK_UP2_EFFECT = "attack", DEFENSE_UP2_EFFECT = "defense", SPEED_UP2_EFFECT = "speed",
  SP_ATK_UP2_EFFECT = "spatk", SP_DEF_UP2_EFFECT = "spdef", EVASION_UP2_EFFECT = "evasion",
}
local SELF_HEAL = { HEAL_EFFECT = true, SYNTHESIS_EFFECT = true, MORNING_SUN_EFFECT = true,
                    MOONLIGHT_EFFECT = true }

local function speedOf(b) return stat(b, "speed") end

-- a status move aimed at one foe
local function statusValue(battle, user, target, def)
  local fx = def.effect or ""
  local acc = accuracy(def)
  local st = target.mon.status
  local side = battle.sides and battle.sides[target.isPlayer and 1 or 2]
  local guarded = side and side.safeguard or target.safeguardTurns
  if fx == "SLEEP_EFFECT" then
    if st or guarded then return 0 end
    return 55 * acc
  elseif fx == "PARALYZE_EFFECT" then
    if st or guarded or eff(def.type, target) == 0 then return 0 end
    return (speedOf(target) > speedOf(user) and 45 or 32) * acc
  elseif fx == "POISON_EFFECT" or fx == "TOXIC_EFFECT" then
    if st or guarded or hasType(target, "POISON") or hasType(target, "STEEL") then return 0 end
    return (hpPct(target) > 50 and 30 or 12) * acc
  elseif fx == "CONFUSION_EFFECT" or fx == "SWAGGER_EFFECT" then
    if target.confusedTurns or guarded then return 0 end
    return 26 * acc
  elseif fx == "LEECH_SEED_EFFECT" then
    if target.leechSeeded or hasType(target, "GRASS") then return 0 end
    return 24 * acc
  elseif fx == "MEAN_LOOK_EFFECT" then
    if battle.meanLookHolds and battle:meanLookHolds(target) then return 0 end
    return 6 * acc
  elseif fx == "ATTRACT_EFFECT" then
    return 14 * acc
  elseif STAT_DOWN[fx] then
    -- worth a turn early on, not over a hit that does real damage
    if stageOf(target, STAT_DOWN[fx]) <= -2 or (user.turnsOut or 0) > 3 then return 0 end
    return (hpPct(user) > 50 and 7 or 2) * acc
  elseif fx == "SPLASH_EFFECT" then
    return 0
  end
  return 8 * acc
end

-- a move the user aims at itself or its side
local function selfValue(battle, user, def)
  local fx = def.effect or ""
  local pct = hpPct(user)
  local side = battle.sides and battle.sides[user.isPlayer and 1 or 2]
  if SELF_HEAL[fx] then
    if pct < 35 then return 80 elseif pct < 60 then return 35 end
    return 0
  elseif fx == "REST_EFFECT" or def.id == "REST" then
    if pct < 35 or (user.mon.status and pct < 60) then return 60 end
    return 0
  elseif STAT_UP[fx] then
    if stageOf(user, STAT_UP[fx]) >= 2 then return 0 end
    return (pct > 70 and (user.turnsOut or 0) <= 2) and 22 or 6
  elseif fx == "REFLECT_EFFECT" then
    return (side and side.reflect) and 0 or 20
  elseif fx == "LIGHT_SCREEN_EFFECT" then
    return (side and side.lightScreen) and 0 or 20
  elseif fx == "PROTECT_EFFECT" or fx == "ENDURE_EFFECT" then
    if user.protectedLastTurn or (user.protectCount or 0) > 0 then return 0 end
    return pct < 30 and 18 or 4
  elseif fx == "SUBSTITUTE_EFFECT" then
    if user.substituteHP or pct < 30 then return 0 end
    return 15
  elseif fx == "BELLY_DRUM_EFFECT" then
    return (pct > 75 and stageOf(user, "attack") < 6) and 25 or 0
  elseif fx == "SPLASH_EFFECT" then
    return 0
  end
  return 8
end

-- reset the shared plan; the battle calls this before the foes choose
function DoublesAI.beginTurn(battle)
  battle.doublesAIPlan = {}
end

-- Best (move, target) for `user` among `usable` (entries of user.curMoves).
-- `target` is nil for a move that picks its own (spread, self).  Answers nil
-- when nothing scores at all, so the caller keeps its old behaviour.
function DoublesAI.choose(battle, user, usable)
  if not (battle and user and usable and usable[1]) then return nil end
  local foes = {}
  for _, f in ipairs(battle:foesOf(user)) do if alive(f) then foes[#foes + 1] = f end end
  if #foes == 0 then return nil end
  local ally = battle.partnerOf and battle:partnerOf(user)
  if not alive(ally) then ally = nil end
  local plan = battle.doublesAIPlan or {}
  battle.doublesAIPlan = plan
  local moves = battle.data and battle.data.moves or {}

  local best, tied = nil, {}
  local function offer(score, mv, target, hits)
    score = math.floor(score * 10 + 0.5)
    if best == nil or score > best then
      best, tied = score, { { mv, target, hits } }
    elseif score == best then
      tied[#tied + 1] = { mv, target, hits }
    end
  end

  for _, mv in ipairs(usable) do
    local def = moves[mv.id]
    if def then
      local kind = Targeting.kindOf(def)
      local acc = accuracy(def)
      local damaging = (tonumber(def.power) or 0) > 0
      local factor = 1
      if TWO_TURN[def.effect] and not (def.effect == "SOLARBEAM_EFFECT" and battle.field
                                       and battle.field.weather == "SUN") then
        factor = 0.55
      elseif def.effect == "HYPER_BEAM_EFFECT" then
        factor = 0.8
      end
      if kind == Targeting.USER or kind == Targeting.OPPONENTS_FIELD or kind == Targeting.ALLY then
        offer(selfValue(battle, user, def), mv, nil, nil)
      elseif kind == Targeting.BOTH or kind == Targeting.FOES_AND_ALLY then
        local total, hits = 0, {}
        for _, f in ipairs(foes) do
          if damaging then
            local d = estimate(battle, user, f, def, #foes > 1 or ally ~= nil)
            total = total + hitValue(plan, f, d) * acc * factor
            hits[f] = d
          else
            total = total + statusValue(battle, user, f, def) * 0.75
          end
        end
        if kind == Targeting.FOES_AND_ALLY and ally and damaging then
          local d = estimate(battle, user, ally, def, true)
          local cost = math.min(d, ally.mon.hp) * 100 / maxHp(ally)
          if d >= ally.mon.hp then cost = cost + 70 end
          total = total - cost * 1.2
        end
        if def.effect == "EXPLODE_EFFECT" and hpPct(user) > 35 then total = total - 120 end
        offer(total, mv, nil, damaging and hits or nil)
      else
        for _, f in ipairs(foes) do
          local s
          if damaging then
            local d = estimate(battle, user, f, def, false)
            s = hitValue(plan, f, d) * acc * factor
            if def.effect == "EXPLODE_EFFECT" and hpPct(user) > 35 then s = s - 120 end
            offer(s, mv, f, { [f] = d })
          else
            offer(statusValue(battle, user, f, def), mv, f, nil)
          end
        end
      end
    end
  end

  if best == nil or best <= 0 then return nil end
  local pick = tied[1]
  if #tied > 1 and battle.rng then pick = tied[battle.rng(1, #tied)] end
  -- what this foe is about to deal, for the one choosing after it
  if pick[3] then
    for f, d in pairs(pick[3]) do plan[f] = (plan[f] or 0) + d end
  end
  return pick[1], pick[2]
end

return DoublesAI
