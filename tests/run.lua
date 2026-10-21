-- Run a co-op suite against a stock Gen2Recomped checkout with this mod on.
--
--   cd <Gen2Recomped checkout>
--   luajit <mod>/tests/run.lua <mod>/tests/coop_lockstep.lua
--
-- The mod is booted the way the engine's loader boots it (its main.lua is
-- handed an api table), then the suite runs exactly as it ran inside the
-- co-op build.  PKM_EAGER=1 loads every engine module first, the way a real
-- boot has most of them loaded before mods run; without it every patch goes
-- in through the lazy `require` searcher.

package.path = "./?.lua;./?/init.lua;" .. package.path

local here = arg[0]:match("^(.*)/tests/[^/]*$") or "."
local suite = assert(arg[1], "usage: run.lua <suite.lua>")

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local quiet = os.getenv("PKM_VERBOSE") ~= "1"
local logLines = {}
local function logger(level)
  return function(_, fmt, ...)
    local line = ("[PkMultiplayer %s] " .. fmt):format(level, ...)
    logLines[#logLines + 1] = line
    if not quiet or level ~= "info" then io.stderr:write(line, "\n") end
  end
end

local api = {
  id = "PkMultiplayer",
  version = "test",
  path = here,
  generation = tonumber(os.getenv("PKM_GENERATION") or "2"),
  log = { info = logger("info"), warn = logger("warn"), error = logger("error") },
  hooks = { wrap = function() end },
}
function api:read(rel) return readFile(here .. "/" .. rel) end

if os.getenv("PKM_EAGER") == "1" then
  local index = dofile(here .. "/lib/patches/index.lua")
  for _, spec in ipairs(index.modules) do require(spec.module) end
  require("src.core.Game")
  require("src.core.SaveData")
  require("src.script.Gen2Commands")
end

-- PKM_PRE: a script to run first, standing in for a mod loaded before this one
if os.getenv("PKM_PRE") then dofile(os.getenv("PKM_PRE")) end

local main = assert(loadfile(here .. "/main.lua"))
main(api)

-- the suites sit beside this file; `require("tests.x")` still means the
-- engine's own tests/ (harness, fixtures, love stub)
arg = { [0] = suite }
dofile(suite)
