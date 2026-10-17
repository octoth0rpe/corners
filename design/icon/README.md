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
  See [Making the `.icon` in Icon Composer](#making-the-icon-in-icon-composer).
- `menubar-template.svg`: 18×18 pt glyph, black on transparent. Add it to the
  asset catalog with "Render As: Template Image" and "Preserve Vector Data".
  macOS colors it for light, dark, and highlighted menu bars, so it needs no
  dark variant.

## Making the `.icon` in Icon Composer

The app icon is still an `AppIcon.appiconset` of PNGs rendered from the light SVG, so
the Dock and Finder always show the light icon. An Icon Composer `.icon` adds Dark,
Clear and Tinted appearances. Open Icon Composer (Xcode ▸ Open Developer Tool ▸ Icon
Composer) and save a new document as `Corners/AppIcon.icon`.

1. **Background:** solid `#EEF7F3`. Don't import a background shape; the rounded
   square comes from the system.
2. **Layers:** `layers/tile-primary.svg` and `layers/tiles-secondary.svg`, each in its
   own group, so the lit tile can sit forward or glow a little differently from the
   other three.
3. **Effects:** flat tiles look best with subtle Liquid Glass. Start low.
4. **Dark:** with the Dark appearance selected, set the background to `#0F1E1A`, the
   lit tile to `#3CC79C` and the other tiles to `#24493D`.
5. Check Clear and Tinted, then save.

Then add `AppIcon.icon` to the app target in `project.yml`, remove
`Assets.xcassets/AppIcon.appiconset` so the two don't share a name, and keep the
`AboutIcon` image set for the About window.
