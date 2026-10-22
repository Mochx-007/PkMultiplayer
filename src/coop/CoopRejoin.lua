-- src/coop/CoopRejoin.lua
-- PICKING THE LINK BACK UP.  The transport already rides out a short drop
-- (CoopNet's reconnect window); this covers the rest -- a window that ran
-- out, a game that was closed, the next evening's session.  The save
-- remembers the last link (save.coopLink: which end you were, the host's
-- address, the partner's name), and when that save is back on the overworld
-- with nothing linked:
--   * the host listens again at once;
--   * the guest dials the host every RETRY_EVERY seconds, quietly, for up
--     to MAX_TRIES tries.
-- DISCONNECT in the menu means it: no more tries until the save is loaded
-- again.  START -> CO-OP -> RECONNECT tries right away.  Switched off in
-- MODS -> PkMultiplayer -> OPTIONS -> AUTO RECONNECT.

local CoopManager = require("src.coop.CoopManager")
local CoopNet = require("src.coop.CoopNet")
local CoopLog = require("src.coop.CoopLog")

local CoopRejoin = {}

CoopRejoin.RETRY_EVERY = 20
CoopRejoin.MAX_TRIES = 15
-- seconds on the overworld before the first try, so a save that is only
-- passing through (the title's CONTINUE, a soft reset) is not dialed out of
CoopRejoin.SETTLE = 2

-- per loaded save: { save = <table>, tries, timer, stopped, settled }
CoopRejoin.state = nil

-- the mod's AUTO RECONNECT switch (main.lua publishes the options)
CoopRejoin.enabled = function()
  local opts = package.loaded["pkmultiplayer.options"]
  return not (opts and opts.on) or opts.on("autoReconnect")
end

local function stateFor(save)
  local st = CoopRejoin.state
  if not st or st.save ~= save then
    st = { save = save, tries = 0, timer = 0, settled = 0 }
    CoopRejoin.state = st
  end
  return st
end

-- what the save keeps about this link, refreshed every time it comes up
function CoopRejoin.remember(game)
  local save = game and game.save
  local net = CoopManager.net
  if not (save and net) then return end
  local link = { role = CoopManager.isHost and "host" or "guest",
                 port = tonumber(net.port) or CoopNet.DEFAULT_PORT,
                 partner = CoopManager.partner.name }
  if not CoopManager.isHost then
    link.ip = tostring(net.address or ""):match("^([^:]+)")
  end
  save.coopLink = link
  local st = stateFor(save)
  st.tries, st.timer, st.stopped = 0, 0, nil
end

local function idle()
  local net = CoopManager.net
  return not net or net.closed
end

-- one attempt: listen (host) or dial (guest).  `manual` is the menu row.
function CoopRejoin.try(game, manual)
  local save = game and game.save
  local link = save and save.coopLink
  if not link then return false end
  local st = stateFor(save)
  st.stopped = nil
  local who = link.partner or "PARTNER"
  if link.role == "host" then
    if CoopManager.host(link.port) then
      CoopManager.showStatus("Waiting for " .. who .. "...", 3)
      return true
    end
    if manual then CoopManager.showStatus("Couldn't open port " .. tostring(link.port), 3) end
    return false
  end
  if not link.ip then return false end
  st.tries = st.tries + 1
  if CoopManager.join(link.ip, link.port) then
    if manual or st.tries == 1 then
      CoopManager.showStatus("Looking for " .. who .. "...", 3)
    end
    CoopLog.info("REJOIN", ("dialing %s:%d (try %d)"):format(link.ip, link.port, st.tries))
    return true
  end
  return false
end

-- DISCONNECT from the menu: this save stops trying
function CoopRejoin.stop(game)
  local save = game and game.save
  if save then stateFor(save).stopped = true end
end

CoopManager.onIdleTick("rejoin", function(dt, game, ow)
  local save = game and game.save
  if not (save and save.coopLink and ow and ow.map) then return end
  local st = stateFor(save)
  if CoopManager.connected then
    st.tries, st.timer = 0, 0
    return
  end
  if st.stopped or not CoopRejoin.enabled() then return end
  if not idle() then return end
  if not CoopManager.overworldIdle(game, ow) then return end
  st.settled = st.settled + dt
  if st.settled < CoopRejoin.SETTLE then return end
  if save.coopLink.role == "host" then
    -- one listen; the host then waits as long as the game runs
    if st.tries == 0 then
      st.tries = 1
      CoopRejoin.try(game)
    end
    return
  end
  if st.tries >= CoopRejoin.MAX_TRIES then return end
  st.timer = st.timer - dt
  if st.timer > 0 then return end
  st.timer = CoopRejoin.RETRY_EVERY
  CoopRejoin.try(game)
end)

-- each fresh link is written down
CoopManager.onTick("rejoin", function(dt, game)
  if CoopRejoin.serial ~= CoopManager.linkSerial then
    CoopRejoin.serial = CoopManager.linkSerial
    CoopRejoin.remember(game)
  end
end)

return CoopRejoin
