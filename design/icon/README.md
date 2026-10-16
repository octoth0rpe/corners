# Corners icon

A 2×2 grid of rounded tiles with the top-left tile lit.

## Palette

| Role                     | Light     | Dark      |
| ------------------------ | --------- | --------- |
| Background               | `#EEF7F3` | `#0F1E1A` |
| Primary (top-left tile)  | `#138A68` | `#3CC79C` |
| Secondary (other tiles)  | `#B5DCCB` | `#24493D` |

## Files

- `app-icon-light.svg`, `app-icon-dark.svg`: 1024×1024 artboard. The body is
  824×824 at (100, 100) with radius 185, which matches the macOS icon grid. Tiles
  are 214 with a 52 gap. For Icon Composer, set the background as the fill and
  import the tiles as the foreground layer. macOS generates the Clear and Tinted
  variants from those layers.
- `layers/tile-primary.svg`, `layers/tiles-secondary.svg`: the tiles alone, without the
  background, in light colors, for importing into Icon Composer as two groups.
  Step-by-step instructions for both apps are in the Summon repo at
  `icons/ICON-COMPOSER.md`.
- `menubar-template.svg`: 18×18 pt glyph, black on transparent. Add it to the
  asset catalog with "Render As: Template Image" and "Preserve Vector Data".
  macOS colors it for light, dark, and highlighted menu bars, so it needs no
  dark variant.
