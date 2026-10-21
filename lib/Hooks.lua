-- The co-op build's engine changes that only run BEFORE or AFTER an engine
-- function, as wrappers rather than copies -- so the engine's own body (and
-- whatever upstream changes in it later) stays the engine's.
--
-- Each entry is applied once, when its engine module is first available
-- (lib/Install.lua).  The comments name the co-op build's own lines they
-- stand for.

local Hooks = {}

local function coopManager()
  local ok, CM = pcall(require, "src.coop.CoopManager")
  if ok then return CM end
  return nil
end

local function ctrlDown(withGui)
  local k = love and love.keyboard
  if not (k and k.isDown) then return false end
  if k.isDown("lctrl") or k.isDown("rctrl") then return true end
  return withGui and (k.isDown("lgui") or k.isDown("rgui")) or false
end

-- the partner is told we are gone (coop_bye), so their copy drops our avatar
-- now instead of after the link times out
local function sayGoodbye()
  local CM = package.loaded["src.coop.CoopManager"]
  if CM and CM.disconnect then
    pcall(function()
      if CM.connected or (CM.isConnected and CM.isConnected()) then CM.disconnect() end
    end)
  end
end
Hooks.sayGoodbye = sayGoodbye

-- engine functions a wrapper below expected and did not find
Hooks.missing = {}

-- t[name] = make(original), if t[name] is a function at all
local function wrap(t, label, name, make)
  local original = type(t) == "table" and t[name]
  if type(original) ~= "function" then
    Hooks.missing[#Hooks.missing + 1] = label .. "." .. name
    return
  end
  t[name] = make(original)
end

-- module name -> function(module) that installs its wrappers
Hooks.modules = {}

Hooks.modules["src.core.Game"] = function(Game)
  -- LEAVING THE GAME LEAVES THE CO-OP SESSION: QUIT (or a soft reset)
  -- without saving used to keep the link up while you sat on the title
  wrap(Game, "Game", "returnToTitle", function(returnToTitle)
    return function(self, ...)
      sayGoodbye()
      return returnToTitle(self, ...)
    end
  end)

  -- the co-op pump: once per frame, under battles and menus too
  wrap(Game, "Game", "update", function(update)
    return function(self, dt, ...)
      local a, b, c = update(self, dt, ...)
      local okCoop, coopErr = pcall(function()
        local CM = require("src.coop.CoopManager")
        if CM and CM.update then CM.update(self.overworld, dt) end
      end)
      if not okCoop and coopErr ~= self._lastCoopErr then
        -- reported once per distinct error: a silent failure here is a
        -- silent desync
        self._lastCoopErr = coopErr
        pcall(function() require("src.coop.CoopLog").error("UPDATE", tostring(coopErr)) end)
      end
      return a, b, c
    end
  end)

  -- T: chat (idle overworld, or a co-op double waiting on the partner);
  -- Y: the emote picker (idle overworld).  After the engine's own
  -- delegation to a state that takes keys, as in the co-op build.
  wrap(Game, "Game", "keypressed", function(keypressed)
    return function(self, key, ...)
      local top = self.stack and self.stack:top()
      local delegated = top and top.onKeyPressed
      if not delegated and key == "t" and not ctrlDown(true) then
        local ow = self.overworld
        local coopBattle = top and top.coopDouble == true and top.chooseAction ~= nil
        if coopBattle or (top == ow and ow and not ow.transitioning
           and not (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
           and not ow.engaging and not ow.inBattle
           and not (ow.scriptMoves and #ow.scriptMoves > 0)) then
          local CM = coopManager()
          if CM and CM.openChat then
            CM.openChat(self, ow)
            return
          end
        end
      end
      if not delegated and key == "y" and not ctrlDown(false) then
        local ow = self.overworld
        if top == ow and ow and not ow.transitioning and not ow.engaging and not ow.inBattle
           and not (ow.runner and ow.runner.isRunning and ow.runner:isRunning()) then
          local okE, CoopEmotes = pcall(require, "src.coop.CoopEmotes")
          if okE and CoopEmotes and CoopEmotes.openPicker(self) then return end
        end
      end
      return keypressed(self, key, ...)
    end
  end)

  -- co-op: the partner's game saves too (CoopManager.onLocalSaved)
  wrap(Game, "Game", "writeSave", function(writeSave)
    return function(self, ...)
      local result = writeSave(self, ...)
      pcall(function()
        local CM = require("src.coop.CoopManager")
        if CM.onLocalSaved then CM.onLocalSaved(result) end
      end)
      return result
    end
  end)

  -- An early co-op build wrote every hit's remaining HP into mon.stats.hp,
  -- shrinking the maximum for good.  A Gen 1/2 maximum is a pure function of
  -- species, level, DVs and stat exp, so a save carrying a lower one gets it
  -- back.
  wrap(Game, "Game", "restoreSave", function(restoreSave)
    return function(self, loaded, ...)
      local GV = require("src.core.GameVersion")
      if type(loaded) == "table" and (GV.isGen1() or GV.isGen2()) then
        local Stats = require("src.pokemon.Stats")
        for _, mon in ipairs(loaded.party or {}) do
          local def = type(mon) == "table" and mon.species and self.data.pokemon
                      and self.data.pokemon[mon.species]
          if def and mon.stats and mon.level and mon.dvs then
            local ok, calc = pcall(Stats.calc, def, mon.level, mon.dvs, mon.statExp)
            if ok and calc and calc.hp and (mon.stats.hp or 0) < calc.hp then
              mon.stats.hp = calc.hp
            end
          end
        end
      end
      return restoreSave(self, loaded, ...)
    end
  end)
end

Hooks.modules["src.core.SaveData"] = function(SaveData)
  -- story state the old co-op sharing left half-copied (src/coop/CoopStory)
  wrap(SaveData, "SaveData", "load", function(load)
    return function(...)
      local data, recovered = load(...)
      if type(data) == "table" then
        pcall(function() require("src.coop.CoopStory").repairSave(data) end)
      end
      return data, recovered
    end
  end)
end

Hooks.modules["src.render.TextBox"] = function(TextBox)
  -- the partner sees a "..." over us while a box is up
  wrap(TextBox, "TextBox", "new", function(new)
    return function(...)
      local self = new(...)
      if type(self) == "table" then
        self.isTextBox = true
        pcall(function()
          local CM = coopManager()
          if CM and CM.setInDialogue then CM.setInDialogue(true) end
        end)
      end
      return self
    end
  end)
end

Hooks.modules["src.ui.Menu"] = function(Menu)
  -- opts.header: a one-line title in its own box over the menu ("VS
  -- FALKNER"); Menu:draw (lib/patches/Menu.lua) draws it
  wrap(Menu, "Menu", "new", function(new)
    return function(game, items, opts, ...)
      local self = new(game, items, opts, ...)
      if type(self) == "table" and type(opts) == "table" then self.header = opts.header end
      return self
    end
  end)
end

Hooks.modules["src.battle.TrainerAI"] = function(TrainerAI)
  -- a MEAN LOOK / SPIDER WEB (or a Gen 2 WRAP) holds the foe in as well
  wrap(TrainerAI, "TrainerAI", "switchAction", function(switchAction)
    return function(battle, ...)
      if battle and not battle.arena and battle.canRecall
         and not battle:canRecall(battle.enemy) then
        return nil
      end
      return switchAction(battle, ...)
    end
  end)
end

Hooks.modules["src.battle.Damage"] = function(Damage)
  -- A Gen 2 co-op double has no doubles numbers in its ruleset and passes
  -- HeartGold/SoulSilver's on opts (BattleState:computeDamage); the ruleset's
  -- own numbers, where it has them, still win.
  local KEYS = { "spreadNum", "spreadDen", "screenDoublesNum", "screenDoublesDen" }
  wrap(Damage, "Damage", "compute", function(compute)
    return function(ruleset, attacker, defender, move, opts, ...)
      if type(opts) == "table" and type(ruleset) == "table" then
        local fill
        for _, k in ipairs(KEYS) do
          if ruleset[k] == nil and opts[k] ~= nil then
            fill = fill or {}
            fill[k] = opts[k]
          end
        end
        if fill then ruleset = setmetatable(fill, { __index = ruleset }) end
      end
      return compute(ruleset, attacker, defender, move, opts, ...)
    end
  end)
end

Hooks.modules["src.script.Gen2Commands"] = function()
  -- a co-op session sharing a clock shares mom's picked weekday too
  local Commands = require("src.script.Commands")
  local readvar = Commands.g2_readvar
  if type(readvar) ~= "function" then return end
  function Commands.g2_readvar(ctx, var, ...)
    local a, b, c = readvar(ctx, var, ...)
    if var == 11 and ctx and ctx.save then
      local okCM, CM = pcall(require, "src.coop.CoopManager")
      local offset = okCM and CM.dayOffset and CM.dayOffset(ctx.save)
      if offset then
        ctx.g2Var = ((tonumber(os.date("%w")) or 0) + offset) % 7
      end
    end
    return a, b, c
  end
end

Hooks.modules["src.world.OverworldController"] = function(OverworldState)
  -- a wild / trainer battle may become a co-op double (the partner is asked)
  wrap(OverworldState, "OverworldState", "pushBattle", function(pushBattle)
    return function(self, battle, opts, ...)
      local CM = coopManager()
      if CM and CM.promptCoopBattle and CM.promptCoopBattle(self, battle, opts) then
        return
      end
      if CM and CM.setInBattle then CM.setInBattle(true) end
      return pushBattle(self, battle, opts, ...)
    end
  end)

  -- a trainer the partner is already fighting on this map does not spot us
  wrap(OverworldState, "OverworldState", "checkTrainerSight", function(checkTrainerSight)
    return function(self, ...)
      local CM = coopManager()
      if CM and CM.connected then
        local partnerEngaging = CM.isPartnerEngaging and CM.isPartnerEngaging(self.map and self.map.id)
        if partnerEngaging or CM.pendingBattleInvite or CM.activeInviteModal then
          return
        end
      end
      return checkTrainerSight(self, ...)
    end
  end)

  wrap(OverworldState, "OverworldState", "afterBattle", function(afterBattle)
    return function(self, result, battle, ...)
      local CM = coopManager()
      if CM then
        if CM.setInBattle then CM.setInBattle(false) end
        CM.partnerEngagingTrainer = nil
      end
      local okCB, CoopBattle = pcall(require, "src.coop.CoopBattle")
      if okCB and CoopBattle then
        CoopBattle.active = false
        CoopBattle.waitingForPartner = false
        CoopBattle.currentBattle = nil
      end
      -- back from a battle, every NPC on the player's tile is hushed so the
      -- player is never re-engaged before taking a step
      if self.player then
        local hush = { cellX = self.player.cellX, cellY = self.player.cellY }
        for _, n in ipairs(self.npcs or {}) do hush[n] = true end
        self.spotHush = hush
      end
      self.engaging = false
      self.emote = nil
      return afterBattle(self, result, battle, ...)
    end
  end)

  -- the partner's avatar, emotes and chat bubble (world pass), and the
  -- co-op overlays (UI pass)
  wrap(OverworldState, "OverworldState", "drawWorld", function(drawWorld)
    return function(self, ...)
      local a, b, c = drawWorld(self, ...)
      local CM = coopManager()
      if CM and CM.drawWorld then CM.drawWorld(self) end
      return a, b, c
    end
  end)

  wrap(OverworldState, "OverworldState", "drawUI", function(drawUI)
    return function(self, ...)
      local a, b, c = drawUI(self, ...)
      local CM = coopManager()
      if CM and CM.drawUI then CM.drawUI(self) end
      return a, b, c
    end
  end)
end

-- ui.start_menu.items: the CO-OP (LAN) row, ahead of MODS / QUIT
function Hooks.startMenuItems(next, game, items)
  items = next(game, items)
  if type(items) ~= "table" then return items end
  local Strings = require("src.core.Strings")
  local row = { label = Strings("CO-OP (LAN)"), onSelect = function()
    local CoopMenu = require("src.coop.CoopMenu")
    game.stack:push(CoopMenu.new(game))
  end }
  local at = #items + 1
  for i, item in ipairs(items) do
    if item.label == Strings("MODS") or item.label == Strings("QUIT") then
      at = i
      break
    end
  end
  table.insert(items, at, row)
  return items
end

-- Closing the window says goodbye as well.
function Hooks.installQuit()
  if not love or Hooks._quitWrapped then return end
  Hooks._quitWrapped = true
  local quit = love.quit
  love.quit = function(...)
    sayGoodbye()
    if quit then return quit(...) end
  end
end

return Hooks
