-- (tools/check_patches.py) rebuild every co-op function from its base, as
-- is and with upstream "changed" under it.
package.path = "lib/?.lua;" .. package.path
local T = require("Transplant")
local E = dofile(arg[1])
local MARK = "  local __upstream_drift = true -- PKM drift probe"

local function lines(s)
  local t = {}
  for l in (s .. "\n"):gmatch("([^\n]*)\n") do t[#t + 1] = l end
  return t
end

local exact, drift, total = 0, 0, 0
for stem, units in pairs(E) do
  local f = io.open("lib/patches/" .. stem .. ".lua")
  if f then
    f:close()
    local P = dofile("lib/patches/" .. stem .. ".lua")
    for _, u in ipairs(P.units) do
      total = total + 1
      local want = units[u.name] and units[u.name].new
      local src = u.from and units._all[u.from] or (units[u.name] and units[u.name].base)
      local got, why = T.build(src, u)
      if got == want then
        exact = exact + 1
      else
        print(("FAIL %s %s: rebuilt text differs (%s)"):format(stem, u.name, tostring(why)))
      end
      if u.text then
        drift = drift + 1
      else
        local L = lines(src)
        table.insert(L, 2, MARK)
        local moved = T.build(table.concat(L, "\n"), u)
        local ok = false
        if moved then
          local G = lines(moved)
          for i = #G, 1, -1 do if G[i] == MARK then table.remove(G, i) end end
          ok = table.concat(G, "\n") == want
        end
        if ok then
          drift = drift + 1
        else
          print(("FAIL %s %s: edits do not survive an upstream change"):format(stem, u.name))
        end
      end
    end
  end
end
print(("%d/%d functions rebuilt exactly, %d/%d with upstream changed under them")
      :format(exact, total, drift, total))
if exact < total or drift < total then os.exit(1) end
