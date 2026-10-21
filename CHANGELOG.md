# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

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
