# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 1.3.0

Works with a 1.2.0 partner (same link protocol, 8); they just do not see
your walking Pokemon until they update.

### Added

- **Your Pokemon follows you**, the way it does in HeartGold / SoulSilver:
  the first party Pokemon that is not fainted (and not an egg) walks one
  cell behind you, wearing its party menu icon -- the cartridge's own
  overworld Pokemon sheets, from your ROM import.  It changes when the lead
  does, hides on the bike and while surfing, crosses map seams with you,
  and A on it shows how it feels about you (its friendship).  Gold, Silver
  and Crystal.  ON by default: MODS -> PkMultiplayer -> OPTIONS ->
  POKEMON FOLLOWS YOU.
- In co-op you see your partner's walking Pokemon behind them too.

### Fixed

- The README still said the emotes could only be drawn bubbles; since 1.2.0
  they are the cartridge's own when you import your ROM for the mod.

## 1.2.0

Both players need 1.2.0: the link protocol is now 8 (the warp request is new).

### Added

- **The cartridge's own emote bubbles again.**  Optional: import your Gold,
  Silver or Crystal ROM for this mod in the MODS panel (IMPORT on the mod's
  row).  The eight bubbles are cut from it once on your device and used for
  the co-op emotes and for every trainer's "!", as in the old co-op build.
  Nothing from the ROM ships with the mod.
- Without the ROM, the emotes are now this mod's own drawn 16x16 bubbles
  instead of the tiny text pills.

### Changed

- **WARP TO PARTNER, much harder to use:** only to a town or city you have
  already visited (the places FLY can take you), your partner has to say
  YES, and it recharges for ten minutes.  A NO costs no recharge.

### Fixed

- TRADE and BATTLE P1 VS P2 with no POKeMON crashed the game (the link
  battle has no lead to send out).  Now you cannot ask without a POKeMON, a
  partner with none declines on their own, and both are told why.

## 1.1.0

### Added

- Playable on phones: a **CHAT** row at the top of the linked co-op menu, and
  **SELECT** opens the chat in a co-op double (on the action menu, or while
  waiting for the partner) -- the touch layout has no T key.  On a phone the
  chat raises the on-screen keyboard, and **A** brings it back if it was
  swiped away.

### Fixed

- The ZeroTier address now shows on iOS and Android.  It is found by asking
  the OS which address it would route to each of ZeroTier's address pools,
  which needs no shell; the `ip` / `ipconfig` lookups remain as the fallback
  on desktops (for networks on a custom range).
- Closing the chat no longer turns text input off on desktops.
- The linked co-op menu fits its box again: no RESUME row (B closes the
  menu), the first row clear of the border, and PARTNER HEAL short enough
  not to run past the edge.

## 1.0.0

### Added

- The co-op from the PkMplayer fork (its "v29"), now as a mod for the
  official Gen2Recomped: no fork to download any more.
- The link (LAN / ZeroTier), the partner's avatar, chat and emotes.
- Co-op double battles in lockstep, with HeartGold/SoulSilver's doubles
  rules and a doubles AI for the foe.
- Shared story events, Hall of Fame, Bug-Catching Contest, clock and saves.
- Trades through the Cable Club over the link; P1 vs P2 battles.
