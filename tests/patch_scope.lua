-- EVERY NAME A PATCH USES RESOLVES.
--
-- A transplanted function reads the engine file's locals through
-- lib/Transplant.lua's environment.  A name that resolves to nothing there is
-- a local the engine renamed or dropped, and the function would only fail
-- when that line runs -- maybe mid-battle.  This boots the mod, loads every
-- patched engine module, and asks the environment for every global the
-- built co-op versions read (luajit -bl), and checks that no patched function's
-- upstream copy changed since the patches were generated.
--
--   cd <Gen2Recomped checkout>; luajit <mod>/tests/run.lua <mod>/tests/patch_scope.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local STATE = assert(rawget(_G, "__PKMULTIPLAYER"), "run through tests/run.lua")
local here = STATE.mod.path
local index = dofile(here .. "/lib/patches/index.lua")

-- globals that are legitimately absent outside a real LOVE boot
local MAY_BE_NIL = { Game = true }

local fails, checked = 0, 0
for _, spec in ipairs(index.modules) do
  require(spec.module)
  local report = STATE.reports[spec.module]
  if not report then
    fails = fails + 1
    print("FAIL " .. spec.module .. ": never patched")
  else
    if #report.drift > 0 then
      fails = fails + 1
      print("FAIL " .. spec.module .. ": changed upstream: " .. table.concat(report.drift, ", "))
    end
    if #report.failed > 0 then
      fails = fails + 1
      print("FAIL " .. spec.module .. ": edits not placed: " .. table.concat(report.failed, "; "))
    end
    if #report.missing > 0 then
      fails = fails + 1
      print("FAIL " .. spec.module .. ": missing upstream: " .. table.concat(report.missing, ", "))
    end
    local tmp = os.tmpname()
    local f = assert(io.open(tmp, "wb"))
    f:write(report.source or "")
    f:close()
    local listing = io.popen("luajit -bl " .. tmp)
    local seen = {}
    for line in listing:lines() do
      local name = line:match('GGET%s+%d+%s+%d+%s+;%s+"([^"]+)"')
      if name and not seen[name] then
        seen[name] = true
        checked = checked + 1
        local inScope = false
        for _, n in ipairs(spec.scope) do if n == name then inScope = true end end
        if inScope and not report.refs[name] and report.env[name] == nil then
          -- an engine local nothing captures: the patch must declare it
          fails = fails + 1
          print(("FAIL %s: engine local `%s` is out of reach"):format(spec.patch, name))
        elseif not inScope and report.env[name] == nil and not MAY_BE_NIL[name] then
          fails = fails + 1
          print(("FAIL %s: `%s` resolves to nothing"):format(spec.patch, name))
        end
      end
    end
    listing:close()
    os.remove(tmp)
  end
end

print(("%d names in %d patches checked, %d failures"):format(checked, #index.modules, fails))
if fails > 0 then os.exit(1) end
