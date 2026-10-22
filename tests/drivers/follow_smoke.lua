-- The walking Pokemon (src/follow/FollowMon.lua) in a real game, the mod
-- installed:
--
--   SHOT_DIR=/tmp/pkm POKEPORT_VERSION=gold POKEPORT_DRIVER=<mod>/tests/drivers/follow_smoke.lua love .
--
-- It spawns behind the player as the lead's party icon, trails one cell
-- behind, answers A, hands over to the next Pokemon when the lead faints,
-- hides on the bike, crosses a map seam as the same object (Route 29 into
-- Cherrygrove), and goes away when switched off.  Screenshots in SHOT_DIR.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/pkm"
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
  end
  local function follower()
    for _, n in ipairs(game.overworld.npcs or {}) do
      if n.pkmFollower then return n end
    end
  end

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local save = U.freshSave(game)
  save.player.name = "MOCHI"
  for _, n in ipairs({ 158, 25, 16 }) do
    table.insert(save.party, Pokemon.new(game.data, ("SPECIES_%03d"):format(n), 14))
  end
  U.teleport(game, "NEW_BARK_TOWN", 6, 8, "down")
  local ow = game.overworld
  U.wait(10)
  local f = follower()
  check(f ~= nil, "spawned on map entry")
  check(f and f.spriteName == "SPRITE_MON_158", "it is the lead's icon (" .. tostring(f and f.spriteName) .. ")")

  U.hold(game, "right", 40); U.wait(30)
  f = follower()
  local p = ow.player
  check(f and f.cellX == p.cellX - 1 and f.cellY == p.cellY, "one cell behind, walking right")
  U.hold(game, "down", 40); U.wait(30)
  f = follower()
  check(f and f.cellX == p.cellX and f.cellY == p.cellY - 1, "one cell behind, walking down")
  U.shot(game, DIR .. "/follow_walk.png")

  U.tap(game, "up"); U.wait(8)
  U.tap(game, "a"); U.wait(150)
  check(game.stack:top() ~= ow, "A on it opens its line")
  U.shot(game, DIR .. "/follow_talk.png")
  for _ = 1, 40 do
    if game.stack:top() == ow then break end
    U.tap(game, "a"); U.wait(15)
  end
  check(game.stack:top() == ow, "back on the overworld")

  save.party[1].hp = 0
  U.wait(5)
  f = follower()
  check(f and f.spriteName == "SPRITE_MON_025", "a fainted lead hands over to the next")
  save.party[1].hp = 20

  save.onBike = true; U.wait(5)
  check(follower() == nil, "hidden on the bike")
  save.onBike = false; U.wait(5)
  check(follower() ~= nil, "back off the bike")

  -- a seam (New Bark's own west exit is held by Elm's scene on a fresh save)
  U.teleport(game, "ROUTE_29", 3, 6, "left")
  U.wait(10)
  local before = follower()
  for _ = 1, 6 do U.hold(game, "left", 16); U.wait(2) end
  U.wait(40)
  ow = game.overworld
  local after = follower()
  p = ow.player
  check(ow.map.id == "CHERRYGROVE_CITY", "crossed into " .. tostring(ow.map.id))
  check(after ~= nil and after == before, "the same follower crossed the seam")
  check(after and after.cellX == p.cellX + 1 and after.cellY == p.cellY, "one cell behind after the seam")
  U.shot(game, DIR .. "/follow_seam.png")

  local FollowMon = require("src.follow.FollowMon")
  local enabled = FollowMon.enabled
  FollowMon.enabled = function() return false end
  U.wait(3)
  check(follower() == nil, "switched off")
  FollowMon.enabled = enabled

  U.log("RESULT", fails == 0 and "PASS" or ("FAIL " .. fails))
  love.event.quit(fails == 0 and 0 or 1)
end
