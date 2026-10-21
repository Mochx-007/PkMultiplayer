# PkMultiplayer — co-op online para Gen2Recomped

Juega **Pokémon Oro, Plata o Cristal** (y Rojo/Azul/Amarillo) con un amigo en el
mismo mundo: os veis caminar, chateáis, vivís los eventos de la historia juntos
y peleáis contra los entrenadores en **combates dobles 2 contra 2**.

Es un **mod** para el [Gen2Recomped](https://github.com/UNDERdecoded/Gen2Recomped)
oficial. No hace falta descargar ningún fork del juego, solo este zip.

*English below.*

## Instalación

1. Ten el **Gen2Recomped oficial** instalado, con tu ROM de Oro/Plata/Cristal ya importada.
2. Descarga `PkMultiplayer-<versión>.zip` de
   [Releases](https://github.com/Mochx-007/PkMultiplayer/releases).
3. En el launcher, abre la pestaña **MODS** y pulsa **Import mod .zip**, o
   arrastra el zip a la ventana. Comprueba que el mod está activado.
4. Abre el juego. Los **dos jugadores** necesitan el mod, y en la misma versión.

El launcher te avisa cuando sale una versión nueva (el mod comprueba sus
releases de GitHub).

## Cómo conectarse

- **Misma red (LAN):** uno pulsa START → **CO-OP (LAN)** → **HOST**. El otro
  entra en **JOIN** y escribe la IP que le aparece al host.
- **Por internet:** usad [ZeroTier](https://www.zerotier.com/) (una red
  virtual gratuita). Uníos los dos a la misma red y usad la IP de ZeroTier
  del host. El puerto es el **7777**.
- Desde el título también podéis elegir **NEW CO-OP GAME** o **CONTINUE CO-OP**
  para empezar o seguir una partida juntos.

## En el móvil (iOS / Android)

| | |
|---|---|
| Chat | START → CO-OP (LAN) → **CHAT**; en un combate doble, **SELECT**. Se abre el teclado del teléfono, la tecla de retorno envía y **A** vuelve a sacar el teclado si lo cerraste. |
| Emotes | START → CO-OP (LAN) → **EMOTE** |
| IP de ZeroTier | se muestra sola si la app de ZeroTier está conectada (redes con los rangos automáticos de ZeroTier Central) |

## Qué incluye

| | |
|---|---|
| Mundo compartido | ves a tu compañero en tu mapa, con su nombre encima |
| Chat | tecla **T** (también durante un combate doble); en móvil, ver arriba |
| Emotes | tecla **Y** |
| Combates dobles | contra entrenadores, en lockstep, con las reglas de dobles de HeartGold/SoulSilver y una IA rival pensada para dobles |
| Historia compartida | los eventos que vive uno los vive el otro; las batallas importantes se preguntan antes |
| Extras | intercambios por el Cable Club, P1 vs P2, objetos para los Pokémon del compañero, ir hasta tu compañero (warp), Concurso de Bichos y Salón de la Fama compartidos, reloj compartido |

Menú co-op (START → CO-OP (LAN) estando conectado): CHAT, WARP TO PARTNER, ITEM
FOR PARTNER, STORY SYNC, PARTNER HEAL, TRADE, BATTLE P1 VS P2, EMOTE, DISCONNECT.

## Limitaciones conocidas

- Solo funciona en juegos de **Gen 1 y Gen 2**. En el resto el mod se carga
  pero no hace nada.
- Los emotes se dibujan como globos simples, porque Gen2Recomped no importa
  la hoja de globos del cartucho.
- Si Gen2Recomped cambia mucho las funciones que toca el mod, el mod lo
  detecta y deja ese módulo sin parchear (lo verás en `log.txt`). En ese
  caso hay que actualizar PkMultiplayer.

## Registro (logs)

`coop.log` y `log.txt` están en la carpeta de guardado del juego. Si algo
falla, mándalos al abrir un issue.

---

# PkMultiplayer — online co-op for Gen2Recomped

Two players, one Johto. You see each other walk, chat (**T**) and emote
(**Y**), live the story's events together, trade through the Cable Club and
fight trainers as a **2-vs-2 double battle** in lockstep, with
HeartGold/SoulSilver's doubles rules.

It is a mod for the official [Gen2Recomped](https://github.com/UNDERdecoded/Gen2Recomped).

**Install:** download the zip from Releases. In the launcher open **MODS** →
**Import mod .zip**, or drop the zip on the window. Both players need it.
**Play:** START → **CO-OP (LAN)** → HOST, or JOIN with the host's IP. Over the
internet, use ZeroTier. The port is 7777.

## How it works (for developers)

The co-op needs changes in the middle of about a hundred engine functions.
The mod carries **none of the engine's code**:

- `src/` holds the co-op modules, served to `require` under the names the
  engine asks for.
- `lib/Hooks.lua` wraps the engine functions that only need co-op code
  before or after them.
- `lib/patches/*.lua` are **edits**: where each one goes (the line, plus the
  FNV-1a hashes of the lines around it), how many lines it removes, and the
  co-op's own new lines. Lines the edit only moves or re-indents are named
  by number and hash, not copied.
- `lib/Transplant.lua` reads each engine function's source from the
  player's own copy of the game, applies the edits, and compiles the result
  in an environment that resolves the engine file's locals through the
  upvalues of its own functions. If another mod (for example the bundled
  voxel mod) already wrapped a function, the co-op version goes inside that
  wrapper and the wrapper stays in place. When upstream has changed a
  function, the edits are placed by context. If they cannot be placed, that
  module is left unpatched and the log says so.

### Tests

From a Gen2Recomped checkout:

```sh
luajit <mod>/tests/run.lua <mod>/tests/coop_lockstep.lua       # each suite
luajit <mod>/tests/run.lua <mod>/tests/patch_scope.lua         # every name resolves
PKM_EAGER=1 PKM_PRE=<mod>/tests/foreign_wrapper_pre.lua \
  luajit <mod>/tests/run.lua <mod>/tests/foreign_wrapper.lua   # another mod's wrappers survive
```

`tests/drivers/coop_smoke.lua` runs two real game instances linked over
127.0.0.1 (`PKM_ROLE=host|guest`, see the file).

### Regenerating the patches

`tools/gen_patches.py <checkout> <upstream ref> <co-op ref>` rebuilds
`lib/patches/` from a tree with the co-op changes merged into upstream.
`tools/check_patches.py` with the same arguments checks that every function
is rebuilt byte for byte, and still is when upstream has changed it.

## License

PkMultiplayer's own files are MIT (see `LICENSE`). Gen2Recomped belongs to
its authors and is under its own license. No ROM data is included. Pokémon
is a trademark of Nintendo, Creatures Inc. and GAME FREAK Inc.
