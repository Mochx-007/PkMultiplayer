-- BACK TO THE LAUNCHER AND INTO THE GAME AGAIN, WITH EVERYTHING ALREADY PATCHED.
--
-- Reported from play (log of a session): the launcher's backdrop booted the
-- mod, the game booted it again in the same process, and on that second load
-- most of the patches failed -- "the engine function's source is not
-- readable" -- because the engine's modules still held the FIRST load's
-- co-op functions, and those are not the engine's source to edit.  Updating
-- the mod from the MODS panel did the same, and kept the old version of the
-- mod's own modules in package.loaded besides.
--
-- A second load must put the engine back as it was, patch it afresh with the
-- files on disk now, wrap each function once, and load its own modules anew.
--
--   cd <Gen2Recomped checkout>
--   PKM_EAGER=1 luajit <mod>/tests/run.lua <mod>/tests/reload_patched.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local first = assert(rawget(_G, "__PKMULTIPLAYER"), "run through tests/run.lua")
local here = first.mod.path
local index = dofile(here .. "/lib/patches/index.lua")
for _, spec in ipairs(index.modules) do
  assert(first.applied[spec.module], spec.module .. " not patched by the first load: run with PKM_EAGER=1")
end

local fails = 0
local function check(cond, what)
  print((cond and "ok   " or "FAIL ") .. what)
  if not cond then fails = fails + 1 end
end

local getinfo, getupvalue = debug.getinfo, debug.getupvalue
local function fromFile(f, file)
  local info = type(f) == "function" and getinfo(f, "S")
  local src = info and info.source or ""
  return src:sub(-#file) == file
end

-- the first load's own modules, to tell them from the second's
local oldEmotes = require("src.coop.CoopEmotes")
local oldAI = require("src.battle.DoublesAI")
check(oldEmotes ~= nil and oldAI ~= nil, "fixture: the first load's modules are loaded")

-- the first load's co-op copy of an engine function, for comparison
local BattleState = require("src.battle.BattleState")
local firstResolve = BattleState.resolveTurn

local function boot()
  -- what ModSeams.unwindAll does to the mod's own global
  rawset(_G, "__PKMULTIPLAYER", nil)
  local lines = {}
  local function logger(level)
    return function(_, fmt, ...) lines[#lines + 1] = level .. " " .. fmt:format(...) end
  end
  local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
  end
  local api = {
    id = "PkMultiplayer", version = "test", path = here, generation = 2,
    log = { info = logger("info"), warn = logger("warn"), error = logger("error") },
    hooks = { wrap = function() end },
  }
  function api:read(rel) return readFile(here .. "/" .. rel) end
  assert(loadfile(here .. "/main.lua"))(api)
  return assert(rawget(_G, "__PKMULTIPLAYER")), lines
end

for round = 2, 3 do
  local state, lines = boot()
  check(state ~= first, ("load %d: a new STATE"):format(round))
  local notPatched = {}
  for _, l in ipairs(lines) do
    if l:find("NOT patched", 1, true) or l:find("was NOT patched", 1, true) then
      notPatched[#notPatched + 1] = l:sub(1, 120)
    end
  end
  check(#notPatched == 0, ("load %d: every engine module patched again (%s)"):format(
        round, table.concat(notPatched, " | ")))
  local all = true
  for _, spec in ipairs(index.modules) do
    local r = state.reports[spec.module]
    if not (state.applied[spec.module] and r and #r.failed == 0) then all = false end
  end
  check(all, ("load %d: every module reports a clean patch"):format(round))
end

-- the co-op functions are this load's, built from the engine's own source
check(BattleState.resolveTurn ~= firstResolve, "BattleState:resolveTurn is this load's co-op copy")
check(not fromFile(BattleState.resolveTurn, "src/battle/BattleState.lua"),
      "...and it is the co-op copy, not the engine's")

-- a wrapper wraps the ENGINE's function, once -- not the last load's wrapper
local Game = require("src.core.Game")
local wrapperOfWrapper = false
do
  local i = 1
  while true do
    local name, v = getupvalue(Game.returnToTitle, i)
    if not name then break end
    if type(v) == "function" and not fromFile(v, "src/core/Game.lua") and name == "returnToTitle" then
      wrapperOfWrapper = true
    end
    i = i + 1
  end
end
check(not fromFile(Game.returnToTitle, "src/core/Game.lua"), "Game.returnToTitle is wrapped")
check(not wrapperOfWrapper, "...once: the wrapper holds the engine's function, not an old wrapper")

-- another mod's wrapper (PKM_PRE=tests/foreign_wrapper_pre.lua) is still the
-- one on the field after the reloads, and still reaches the co-op copy
local other = rawget(_G, "__OTHER_MOD_WRAPPERS")
if other then
  check(BattleState.drawHUDs == other.drawHUDs and BattleState.tryRun == other.tryRun,
        "the other mod's wrappers are still on the field")
  local inner
  local i = 1
  while true do
    local name, v = getupvalue(other.tryRun, i)
    if not name then break end
    if name == "innerCanRun" then inner = v end
    i = i + 1
  end
  check(inner ~= nil and not fromFile(inner, "src/battle/BattleState.lua"),
        "...and call this load's co-op copy, not the engine's")
end

-- the mod's own modules are the files on disk now, not the first load's
check(require("src.coop.CoopEmotes") ~= oldEmotes, "CoopEmotes is not the first load's copy")
local newAI = require("src.battle.DoublesAI")
check(newAI ~= oldAI, "DoublesAI is loaded anew")
check(type(require("src.coop.CoopEmotes").forBubble) == "function",
      "the new CoopEmotes has this version's functions")

if fails > 0 then
  print(("reload_patched: %d failure(s)"):format(fails))
  os.exit(1)
end
print("reload_patched: ok")
