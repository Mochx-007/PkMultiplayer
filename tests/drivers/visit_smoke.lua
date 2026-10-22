-- VISITORS: three real game instances.  The host and the guest link as a
-- co-op pair; a third copy VISITS the host's world.  All three stand on
-- Route 29 and must see the other two, and a chat line from each must reach
-- the other two.
--
--   PKM_ROLE=host|guest|visitor PKM_PORT=7800 SHOT_DIR=/tmp/pkm \
--   POKEPORT_VERSION=gold POKEPORT_IDENTITY=<copy> \
--   POKEPORT_DRIVER=<mod>/tests/drivers/visit_smoke.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7800")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local function waitReal(sec, cond)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < sec do
      if cond and cond() then return true end
      U.wait(1)
    end
    return cond and cond() or false
  end

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopVisit = require("src.coop.CoopVisit")
  local save = U.freshSave(game)
  local names = { host = "MOCHI", guest = "TOBY", visitor = "ASH" }
  save.player.name = names[role]
  table.insert(save.party, Pokemon.new(game.data, "SPECIES_025", 10))
  local x = ({ host = 10, guest = 12, visitor = 14 })[role]
  U.teleport(game, "ROUTE_29", x, 8, "down")

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  elseif role == "guest" then
    waitReal(1.5)
    check(CoopManager.join("127.0.0.1", port), "joining")
  else
    waitReal(4)
    check(CoopVisit.visit("127.0.0.1", port + 1), "visiting " .. (port + 1))
  end

  local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
  local want = role == "visitor" and 2 or 1
  check(waitReal(20, function() return count(CoopVisit.avatars) >= want end),
    ("sees %d other(s) walking here (%d)"):format(want, count(CoopVisit.avatars)))
  U.shot(game, DIR .. "/1_world.png")

  if role == "visitor" then
    waitReal(1)
    CoopManager.sendChat("HELLO FROM ASH")
  elseif role == "host" then
    waitReal(3)
    CoopManager.sendChat("HI ASH")
  end
  local function heard(text)
    for _, l in ipairs(CoopManager.chatLog) do if l.text == text then return true end end
    return false
  end
  if role ~= "visitor" then
    check(waitReal(10, function() return heard("HELLO FROM ASH") end), "the visitor's chat arrives")
  end
  if role ~= "host" then
    check(waitReal(10, function() return heard("HI ASH") end), "the host's chat arrives")
  end
  U.shot(game, DIR .. "/2_chat.png")
  waitReal(4)
  if role == "visitor" then CoopVisit.leave() end
  waitReal(3)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
