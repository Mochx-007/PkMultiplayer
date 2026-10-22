-- WATCH between two real game instances: the host fights a wild battle on
-- its own, the guest opens WATCH and sees it.
--
--   PKM_ROLE=host|guest PKM_PORT=7798 SHOT_DIR=/tmp/pkm \
--   POKEPORT_VERSION=gold POKEPORT_IDENTITY=<copy> \
--   POKEPORT_DRIVER=<mod>/tests/drivers/watch_smoke.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7798")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local m = Pokemon.new(game.data, role == "host" and "SPECIES_155" or "SPECIES_158", 12)
  m.moves = { { id = "TACKLE", pp = 35 } }
  table.insert(save.party, m)
  U.teleport(game, "ROUTE29", role == "host" and 10 or 30, 8, "down")

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "ROUTE29" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked")
  U.wait(60)

  if role == "host" then
    local BattleState = require("src.battle.BattleState")
    local ow = game.overworld
    local battle = BattleState.newWild(game, "SPECIES_019", 10)
    battle.onFinish = function(r) ow:afterBattle(r, battle) end
    ow:pushBattle(battle)
    -- drivers outrun the clock: the battle is held open for real seconds
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 6 do U.wait(1) end
    while love.timer.getTime() - t0 < 20 and game.stack:top() == battle do
      U.tap(game, "a"); U.wait(20)
    end
    while love.timer.getTime() - t0 < 24 do U.wait(1) end
  else
    U.wait(60)
    local CoopWatch = require("src.coop.CoopWatch")
    local scr = CoopWatch.open(game)
    local seen = false
    local t0, shots = love.timer.getTime(), 0
    while love.timer.getTime() - t0 < 14 do
      local f = CoopWatch.frame
      if f and f.foe and f.mine then
        if not seen or (love.timer.getTime() - t0) > shots * 2 then
          shots = shots + 1
          U.shot(game, ("%s/watch_%02d.png"):format(DIR, shots))
        end
        seen = true
      end
      U.wait(1)
    end
    check(seen, "the partner's battle shows up")
    check(CoopWatch.frame and CoopWatch.frame.foe and CoopWatch.frame.foe.species == "SPECIES_019",
      "their foe is the wild RATTATA")
    U.tap(game, "b"); U.wait(10)
    check(game.stack:top() == game.overworld, "B closes the screen")
  end
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
