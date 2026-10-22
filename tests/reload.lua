-- LOADED TWICE IN ONE PROCESS.
--
-- Going back to the launcher takes the mod's _G entries back out, but not
-- package.loaders: a second load must not leave two searchers that call each
-- other (stack overflow on the first require of a pending module), and the
-- patches must go in once, for the load that is current.
--
--   cd <Gen2Recomped checkout>; luajit <mod>/tests/run.lua <mod>/tests/reload.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local first = assert(rawget(_G, "__PKMULTIPLAYER"), "run through tests/run.lua")
local here = first.mod.path
local index = dofile(here .. "/lib/patches/index.lua")

local pending
for _, spec in ipairs(index.modules) do
  if first.pending[spec.module] then pending = spec.module break end
end
assert(pending, "nothing pending: run without PKM_EAGER")

-- what ModSeams.unwindAll does to the mod's own global
rawset(_G, "__PKMULTIPLAYER", nil)

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local api = {
  id = "PkMultiplayer", version = "test", path = here, generation = 2,
  log = { info = function() end, warn = function() end, error = function() end },
  hooks = { wrap = function() end },
}
function api:read(rel) return readFile(here .. "/" .. rel) end
assert(loadfile(here .. "/main.lua"))(api)

local second = assert(rawget(_G, "__PKMULTIPLAYER"))
assert(second ~= first, "second load reused the first STATE")

local fails = 0
local function check(cond, what)
  if not cond then fails = fails + 1 print("FAIL " .. what) end
end

local mine = 0
for _, s in ipairs(package.loaders or package.searchers) do
  if s == rawget(package, "__pkmultiplayer_searcher") then mine = mine + 1 end
end
check(mine == 1, ("one searcher of ours in package.loaders (found %d)"):format(mine))

local ok, err = pcall(require, pending)
check(ok, "require " .. pending .. ": " .. tostring(err))
check(second.applied[pending], pending .. " patched for the current load")
check(not first.applied[pending], pending .. " also patched for the stale load")
check(not second.pending[pending], pending .. " still pending")

if fails > 0 then
  print(("reload: %d failure(s)"):format(fails))
  os.exit(1)
end
print("reload: ok (" .. pending .. ")")
