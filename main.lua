-- PkMultiplayer: online co-op for Gen2Recomped, as a mod.
--
-- Two players, each in their own copy of the game, walk the same Johto (or
-- Kanto) together over LAN / ZeroTier: they see each other, chat, emote,
-- trade through the Cable Club, live the story's events together and fight
-- trainers as a double battle, two against two, in lockstep.
--
-- What this file does, in order:
--
--   1. the co-op modules (src/coop/*, DoublesAI, MicroFont) are served to
--      `require` from this folder, under the names the engine asks for;
--   2. the engine functions the co-op build changes are patched in, each
--      when its engine module is first loaded:
--        - lib/Hooks.lua    wrappers, where the co-op code only runs before
--                           or after the engine's own function;
--        - lib/patches/*    edits, where it runs in the middle: applied to
--                           the engine function as the player's own copy of
--                           the game has it, and the result bound to the
--                           engine file's own locals (lib/Transplant.lua) --
--                           the mod itself carries no engine code;
--   3. the start menu gets its CO-OP (LAN) row and closing the window says
--      goodbye to the partner.
--
-- Only Gen 1 and Gen 2 games are touched: on any other generation the mod
-- loads and does nothing.

local mod = ...

-- one record per process: a hot reload (F5) or a second game boot in the same
-- session must not wrap anything twice
local STATE = rawget(_G, "__PKMULTIPLAYER")
if not STATE then
  STATE = { applied = {}, pending = {}, reports = {} }
  rawset(_G, "__PKMULTIPLAYER", STATE)
end
STATE.mod = mod

local function log(level, fmt, ...)
  local l = mod.log
  if l and l[level] then
    l[level](l, fmt, ...)
  end
end

local function source(rel)
  local text = mod:read(rel)
  if not text then
    error(("PkMultiplayer: %s is missing -- reinstall the mod"):format(rel), 0)
  end
  return text
end

local function chunkFor(rel)
  local fn, err = loadstring(source(rel), "@" .. mod.path .. "/" .. rel)
  if not fn then
    error(("PkMultiplayer: %s did not compile: %s"):format(rel, tostring(err)), 0)
  end
  return fn
end

local generation = tonumber(mod.generation) or 1
if generation > 2 then
  log("info", "co-op is for Gen 1 and Gen 2 games; nothing to do on generation %d", generation)
  return
end

-- ------------------------------------------------------- 1. the modules
local MODULES = {
  "src.coop.CoopBattle", "src.coop.CoopBattleInviteModal",
  "src.coop.CoopBattleSelect", "src.coop.CoopChatBox", "src.coop.CoopEmotes",
  "src.coop.CoopLink", "src.coop.CoopLog", "src.coop.CoopManager",
  "src.coop.CoopMenu", "src.coop.CoopNet", "src.coop.CoopNewGame",
  "src.coop.CoopStory", "src.coop.CoopWaitModal", "src.coop.CoopDex",
  "src.coop.CoopRejoin", "src.coop.CoopGift",
  "src.coop.CoopSoulLink", "src.coop.CoopGear",
  "src.coop.CoopWild",
  "src.battle.DoublesAI", "src.render.MicroFont", "src.follow.FollowMon",
}
for _, name in ipairs(MODULES) do
  local rel = name:gsub("%.", "/") .. ".lua"
  if not package.loaded[name] then
    package.preload[name] = function(...)
      return chunkFor(rel)(...)
    end
  end
end

-- the walking Pokemon (src/follow/FollowMon.lua): Gen 2 only, and a switch
-- in the MODS panel
if mod.options and mod.options.define then
  pcall(mod.options.define, mod.options, {
    { key = "follower", type = "toggle", label = "POKEMON FOLLOWS YOU", default = true },
    { key = "autoReconnect", type = "toggle", label = "AUTO RECONNECT", default = true },
  })
end
-- a switch in the MODS panel, read each time (true when the panel is absent);
-- the co-op modules read it through package.loaded, which needs none of them
-- loaded yet
local function option(key)
  if not (mod.options and mod.options.get) then return true end
  local ok, on = pcall(mod.options.get, mod.options, key)
  return not ok or on ~= false
end
package.loaded["pkmultiplayer.options"] = { on = option }
do
  local FollowMon = require("src.follow.FollowMon")
  FollowMon.enabled = function()
    if generation ~= 2 then return false end
    return option("follower")
  end
end

-- ------------------------------------------------------- 2. the patches
local Transplant = chunkFor("lib/Transplant.lua")()
local Hooks = chunkFor("lib/Hooks.lua")()
local index = chunkFor("lib/patches/index.lua")()

-- module name -> list of { kind, run(module) }
local work = {}
local function add(name, fn)
  work[name] = work[name] or {}
  table.insert(work[name], fn)
end

for _, spec in ipairs(index.modules) do
  add(spec.module, function(module)
    local s = {}
    for k, v in pairs(spec) do s[k] = v end
    s.patch = chunkFor(spec.patch)()
    s.chunkname = "@" .. mod.path .. "/" .. spec.patch .. " (applied)"
    local report = Transplant.apply(module, s, function(fmt, ...) log("info", fmt, ...) end)
    STATE.reports[spec.module] = report
    if #report.failed > 0 then
      log("error", "%s was NOT patched -- this Gen2Recomped is too different from %s for "
          .. "these co-op edits (%s); update PkMultiplayer", spec.module, index.base,
          table.concat(report.failed, "; "))
    elseif #report.drift > 0 then
      log("warn", "Gen2Recomped changed %s since PkMultiplayer was made (base %s); the "
          .. "co-op edits were placed by context", table.concat(report.drift, ", "), index.base)
    end
    if #report.missing > 0 then
      log("warn", "%s: not found in this Gen2Recomped: %s", spec.module,
          table.concat(report.missing, ", "))
    end
  end)
end
for name, install in pairs(Hooks.modules) do
  add(name, install)
end

local function applyTo(name, module)
  if STATE.applied[name] or type(module) ~= "table" then return end
  STATE.applied[name] = true
  for _, fn in ipairs(work[name] or {}) do
    local ok, err = pcall(fn, module)
    if not ok then log("error", "patching %s failed: %s", name, tostring(err)) end
  end
end

-- An engine module already loaded is patched now; one that is not yet is
-- patched the moment `require` first loads it, by a searcher that sits in
-- front of the engine's own and hands back the engine's loader, wrapped.
local loaders = package.loaders or package.searchers
for name in pairs(work) do
  if package.loaded[name] then
    applyTo(name, package.loaded[name])
  elseif not STATE.applied[name] then
    STATE.pending[name] = true
  end
end

-- There is only ever one such searcher in the process, kept on `package`:
-- going back to the launcher takes STATE out of _G again, but package.loaders
-- is not among what the engine puts back, so a searcher per load would pile
-- up, and each one, skipping only itself, would call the others, which call
-- it back -- a stack overflow on the first require of a pending module.  The
-- one searcher patches for whichever load's STATE is current.
local searcher = rawget(package, "__pkmultiplayer_searcher")
if not searcher then
  local busy = {}
  searcher = function(name)
    local S = rawget(_G, "__PKMULTIPLAYER")
    if busy[name] or not (S and S.pending[name] and S.apply) then return nil end
    busy[name] = true
    local ok, found, extra = pcall(function()
      for i = 1, #loaders do
        local other = loaders[i]
        if other ~= searcher then
          local loader, x = other(name)
          if type(loader) == "function" then return loader, x end
        end
      end
    end)
    busy[name] = nil
    if not ok then error(found, 0) end
    if not found then return nil end
    return function(...)
      local module = found(...)
      S.pending[name] = nil
      local real = module
      if real == nil then real = package.loaded[name] end
      S.apply(name, real)
      return module
    end, extra
  end
  rawset(package, "__pkmultiplayer_searcher", searcher)
  -- after package.preload (whose own entries win), before the engine's
  table.insert(loaders, 2, searcher)
end
STATE.apply = applyTo

-- ----------------------------------------------- the cartridge's bubbles
-- Only when the player imported their ROM in the MODS panel (lib/Emotes.lua);
-- the field data is loaded before mods, and game.ready catches a reload.
-- (Headless runs -- modkit validate, the tests -- have no images to make.)
if generation == 2 and love and love.filesystem and love.image then
  local Emotes = chunkFor("lib/Emotes.lua")()
  local function installEmotes()
    local Data = package.loaded["src.core.Data"]
    if type(Data) ~= "table" then return end
    local ok, path, why = pcall(Emotes.install, mod, Data)
    if ok and path then
      log("info", "emote bubbles: %s", path)
    elseif not ok then
      log("warn", "emote bubbles: %s", tostring(path))
    elseif why ~= "no ROM imported" then
      log("warn", "emote bubbles: %s", tostring(why))
    end
  end
  installEmotes()
  if mod.events and mod.events.on then
    mod.events:on("game.ready", function() installEmotes() end)
  end
end

-- ------------------------------------------------- 3. menu and goodbye
if mod.hooks and mod.hooks.wrap then
  mod.hooks:wrap("ui.start_menu.items", Hooks.startMenuItems)
end
Hooks.installQuit()

log("info", "PkMultiplayer %s ready (patches built against Gen2Recomped %s)",
    tostring(mod.version), tostring(index.base))
