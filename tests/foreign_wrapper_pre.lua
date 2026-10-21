-- (tests/foreign_wrapper.lua's PKM_PRE) another mod, loaded first, wraps two
-- BattleState methods the co-op build replaces -- the way the bundled voxel
-- mod wraps the battle draws
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local BattleState = require("src.battle.BattleState")
local wrapper = assert(loadstring([[
  local BattleState, calls = ...
  local innerHUDs = BattleState.drawHUDs
  function BattleState:drawHUDs(slide)
    calls.huds = (calls.huds or 0) + 1
    return innerHUDs(self, slide)
  end
  local innerCanRun = BattleState.tryRun
  function BattleState:tryRun(...)
    calls.run = (calls.run or 0) + 1
    return innerCanRun(self, ...)
  end
]], "@mods/other_mod/main.lua"))
_G.__OTHER_MOD_CALLS = {}
wrapper(BattleState, _G.__OTHER_MOD_CALLS)
_G.__OTHER_MOD_WRAPPERS = { drawHUDs = BattleState.drawHUDs, tryRun = BattleState.tryRun }
