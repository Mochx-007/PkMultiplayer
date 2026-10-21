-- CO-OP LIVE CHAT.
--
--   * every change in the chat box goes to the partner at once, on the fast
--     channel, rate-limited, and confirmed on the reliable one when the
--     typing pauses;
--   * a late live packet never brings back text that was already sent or
--     cancelled;
--   * ENTER sends and keeps the box open for the reply; ESC tells the
--     partner you stopped typing;
--   * the box shows the conversation, and a message's time on screen only
--     runs while it is visible.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local SaveData = require("src.core.SaveData")
local CoopManager = require("src.coop.CoopManager")
local CoopChatBox = require("src.coop.CoopChatBox")
require("src.coop.CoopLog").enabled = false

local sent = {}
CoopManager.net = { send = function(_, m, opts) sent[#sent + 1] = { msg = m, fast = opts and opts.fast or false } return true end,
                    isLinked = function() return true end, flush = function() end,
                    update = function() end, poll = function() return {} end }
CoopManager.connected = true
CoopManager.partner.name = "MOCHI"

local function lives()
  local out = {}
  for _, s in ipairs(sent) do if s.msg.type == "coop_chat_live" then out[#out + 1] = s end end
  return out
end

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local save = SaveData.newGame()
save.player.name = "ME"
local game = { data = Data, save = save, stack = newStack(),
               input = { wasPressed = function() return false end, isDown = function() return false end } }
package.loaded["src.core.Game"] = game

-- ---------------------------------------------------------------------
-- sending, letter by letter
-- ---------------------------------------------------------------------

do
  CoopManager.LIVE_EVERY = 0
  sent = {}
  CoopManager.openChat(game, nil)
  local box = game.stack:top()
  T.check(box and box.isChatBox, "T opens the chat box")
  T.check(#lives() == 1 and lives()[1].msg.text == "", "opening the box tells the partner you are typing")
  box.swallowOpenKey = false
  box:onTextInput("h"); box:onTextInput("o"); box:onTextInput("la")
  local l = lives()
  T.check(#l == 4 and l[4].msg.text == "hola", "each change goes out as it is typed (" .. #l .. " packets)")
  T.check(l[4].fast, "...on the fast channel")
  box:onKeyPressed("backspace")
  l = lives()
  T.check(l[#l].msg.text == "hol", "a backspace goes out too")

  -- rate limit: quick keys are folded, the last one still goes out
  CoopManager.LIVE_EVERY = 1e9
  local before = #lives()
  box:onTextInput("a"); box:onTextInput("!")
  T.check(#lives() == before, "inside the rate limit nothing more is sent")
  CoopManager.LIVE_EVERY = 0
  CoopManager.update(nil, 1 / 60)
  l = lives()
  T.check(l[#l].msg.text == "hola!", "the held-back text goes out on the next frame")

  -- a pause is confirmed on the reliable channel
  CoopManager.LIVE_SETTLE = 0
  CoopManager.update(nil, 1 / 60)
  l = lives()
  T.check(l[#l].msg.text == "hola!" and not l[#l].fast, "a pause re-sends the text reliably")

  -- ENTER: the message goes, the box stays for the reply
  sent = {}
  box:onKeyPressed("return")
  local chat
  for _, s in ipairs(sent) do if s.msg.type == "coop_chat" then chat = s.msg end end
  T.check(chat and chat.text == "hola!" and chat.n, "ENTER sends the message with its counter")
  T.check(game.stack:top() == box and box.text == "", "...and the box stays open, empty, for the reply")
  T.check(CoopManager.chatLog[#CoopManager.chatLog].text == "hola!", "your message is in the log")

  -- ESC: the partner's typing line goes away
  sent = {}
  box:onKeyPressed("escape")
  l = lives()
  T.check(#l == 1 and l[1].msg.stop, "ESC tells the partner you stopped typing")
  T.check(game.stack:top() ~= box, "ESC closes the box")
end

-- ---------------------------------------------------------------------
-- receiving
-- ---------------------------------------------------------------------

do
  CoopManager.partnerLiveN = 0
  CoopManager.partnerTyping = nil
  CoopManager.onChatLive({ n = 1, text = "" })
  local name, text, typing = CoopManager.chatBubble()
  T.check(typing and name == "MOCHI" and text:find("typing"), "an empty live line reads 'is typing...'")
  CoopManager.onChatLive({ n = 2, text = "que" })
  CoopManager.onChatLive({ n = 3, text = "que tal" })
  T.check(CoopManager.partnerTyping.text == "que tal", "the partner's text shows live")
  CoopManager.onChatLive({ n = 2, text = "que" })
  T.check(CoopManager.partnerTyping.text == "que tal", "a late, older packet is ignored")
  local lines = CoopManager.chatLines(18, 4)
  T.check(lines[#lines]:find("que tal", 1, true), "the chat box shows the partner's live line")

  CoopManager.onChatReceived("MOCHI", "que tal?", false, 4)
  T.check(CoopManager.partnerTyping == nil, "the sent message replaces the live line")
  CoopManager.onChatLive({ n = 3, text = "que tal" })
  T.check(CoopManager.partnerTyping == nil, "...and a live packet that arrives late cannot bring it back")
  T.check(CoopManager.chatLog[#CoopManager.chatLog].text == "que tal?", "the message is in the log")

  CoopManager.onChatLive({ n = 5, text = "ok" })
  CoopManager.onChatLive({ n = 6, stop = true })
  T.check(CoopManager.partnerTyping == nil, "the partner cancelling clears their line")
  CoopManager.onChatLive({ n = 5, text = "ok" })
  T.check(CoopManager.partnerTyping == nil, "a late packet after a cancel stays dead")
end

-- ---------------------------------------------------------------------
-- a message waits while it is hidden
-- ---------------------------------------------------------------------

do
  CoopManager.partnerTyping = nil
  CoopManager.onChatReceived("MOCHI", "hidden behind a dialogue", false)
  local t0 = CoopManager.activeChatMessage.timer
  for _ = 1, 120 do CoopManager.update(nil, 1 / 60) end   -- nothing drew it
  T.check(CoopManager.activeChatMessage and CoopManager.activeChatMessage.timer == t0,
          "a message nobody could see has not used up its time")
  CoopManager.chatShown = true
  CoopManager.update(nil, 0.5)
  T.check(CoopManager.activeChatMessage.timer < t0, "it counts down once it is on screen")
  T.check(t0 > 3, "a longer message stays up longer (" .. t0 .. " s)")
end

-- the log keeps the last few
do
  for i = 1, 20 do CoopManager.onChatReceived("ME", "msg " .. i, true) end
  T.check(#CoopManager.chatLog == CoopManager.CHAT_LOG_MAX, "the log keeps the last " .. CoopManager.CHAT_LOG_MAX)
  local lines = CoopManager.chatLines(18, 4)
  T.check(#lines == 4 and lines[4]:find("msg 20", 1, true), "the box shows the newest lines")
end

T.finish("co-op live chat")
