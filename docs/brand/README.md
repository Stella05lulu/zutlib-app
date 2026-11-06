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
| `zutlib-lockup-black.svg` | Lockup in one colour, for print. |
| `zutlib-lockup-reversed.svg` | The same on blue or dark backgrounds. |
| `zutlib-app-icon.svg` | App icon master (light mark on a blue tile). |
| `zutlib-maskable.svg` | Android/PWA icon with room for the system's mask. |
| `favicon.svg` | Browser tab icon. |

## Refinement (4 November 2026)

The same concept, made more precise (`refinement-before-after.svg`):

- every point sits on an 8 px grid of the 256 canvas
- the Z's three strokes are all 24 thick, and the notch at the foot is 24 deep to match
- a 6 px radius on the bookmark's top corners and the Z's outer corners; the notch point stays sharp
- the Z sits 8 px above the body's centre, so it looks centred despite the notch
- the wordmark is drawn letters turned into filled outlines, one stroke weight, letters
  32 apart, its x-height lined up with the Z

## How the files are made

Everything comes from one master geometry in `build_brand.py`:

    python docs/brand/build_brand.py      # SVGs here, Android icon vectors
    node docs/brand/render_icons.js       # every PNG icon and splash image

In the app the mark is drawn in code by `ZutLibMark` (`lib/ui/widgets/brand.dart`)
from the same geometry, so it needs no image package. The rest is rendered from the SVGs:

- Android: legacy launcher icons, an adaptive icon (Android 8+) with a monochrome layer
  for themed icons (Android 13), and the splash in light and dark (Android 12+ through the
  system splash, older versions through `launch_background.xml`)
- iOS: every app icon size, and the launch screen in light and dark
- Web: favicon, PWA icons and maskable icons

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
