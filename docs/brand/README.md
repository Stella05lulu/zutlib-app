# ZutLib logo

**The idea:** a bookmark with a Z cut through it. ZutLib keeps your place.
This was concept B from round 1 (`logo-concepts-round-1.png`).

## Files

| File | Use |
|---|---|
| `zutlib-symbol.svg` | The mark in ZutLib blue. Default. |
| `zutlib-symbol-black.svg` | One colour, for print and stamps. |
| `zutlib-symbol-reversed.svg` | On blue or dark backgrounds. |
| `zutlib-lockup.svg` | Mark and wordmark side by side, for headers and posters. |
| `zutlib-lockup-reversed.svg` | The same on blue or dark backgrounds. |
| `zutlib-app-icon.svg` | App icon master (light mark on a blue tile). |
| `zutlib-maskable.svg` | Android/PWA icon with room for the system's mask. |
| `favicon.svg` | Browser tab icon. |

In the app the mark is drawn in code by `ZutLibMark` (`lib/ui/widgets/brand.dart`)
from the same geometry, so it needs no image package. The web icons, favicon, Android
launcher icons and iOS app icons were rendered from these files.

## Colours

| | Hex | Use |
|---|---|---|
| ZutLib blue | `#1D5FC4` | The mark, the main action |
| Paper | `#F6F9FD` | The mark on blue |
| Ink | `#1C2027` | The wordmark, one-colour print |

## Rules

- **Clear space:** keep a gap around the mark at least as wide as the Z's stroke
  (one eighth of the mark's width).
- **Smallest size:** 16 px tall on screen, 6 mm in print. Below that, use the name in text.
- Flat colour only: no gradients, shadows, outlines or glows. Do not stretch, rotate or
  recolour it outside the colours above.
- The wordmark is drawn letters, not a font; use the lockup file instead of typing "zutlib".

Trademark clearance has not been checked. Before using the logo outside the university
project, run a trademark and reverse image search.
