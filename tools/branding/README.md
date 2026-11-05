# Brand asset generation

`LogoText.imageset/sloosh.svg` is the single source of truth for the Latin wordmark.
Launch/auth/About already reference this vector directly. Launcher icons are separate
raster assets: regenerate them whenever the SVG changes.

```sh
cd tools/branding
npm ci
npm run generate
npm test
```

The pinned resvg renderer rasterizes the exact vector at 4×, then downsamples for
antialiased 1024px icons. The original light/dark/tinted colors, horizontal centering,
wordmark width and cinema seats are preserved. Aspect ratio follows the SVG; no
font approximation or independent redraw. Generated icons are opaque RGB, without
pre-rounded corners (iOS supplies the mask). Settings previews are identical to the
light launcher artwork. Background PNGs are clean source layers restored from the
existing icon art, with the old wordmark removed; do not replace them with rendered
icons or old lettering will come back behind future revisions.

«Кириллица» and «Символ» are intentionally distinct alternate icon designs, not
outdated copies of the Latin wordmark. Their artwork, asset identifiers and selection
behavior remain unchanged.

`npm test` compares decoded pixels rather than PNG compression bytes, checks size,
opacity, all three appearances, preview synchronization, and lettering-free source
backgrounds. CI runs this check before the iOS build. Dependencies are development
only and are not bundled into the app.
