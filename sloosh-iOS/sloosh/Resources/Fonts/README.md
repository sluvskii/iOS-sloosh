# Catalog fallback lettering

SlooshCatalogCondensed-SemiBold.ttf is a static weight-600 instance of **Oswald**,
with full upstream character coverage (including Cyrillic and Ё), not a downloaded
web font. Catalog text titles use it when year/genre are hidden, independently of
the image-logo preference (including missing/loading/error image-logo fallbacks).
With year/genre visible, text titles remain SF. Other app typography is unchanged.

Upstream: https://github.com/google/fonts/tree/6c1dbe27dcf7d817d4b62cec033ba77fa8e2a5ec/ofl/oswald
Source: `Oswald[wght].ttf`, SIL Open Font License 1.1 (included in OFL-Oswald.txt).
Original variable TTF SHA-256: 5b38c246e255a12f5712d640d56bcced0472466fc68983d2d0410ec0457c2817
Bundled static TTF SHA-256: e3fc77dbafaac6198106b450d39096d02fbffa075b59fe538bcf4914443125d5

Build provenance: fontTools 4.68.0, `instantiateVariableFont(font, {'wght': 600})`.
No subsetting, glyph changes, or vertical-metric modifications. Name records 1/2/3/4/6/16/17
were set (Windows English + Macintosh English) to the application family/style
“Sloosh Catalog Condensed” / “SemiBold”; PostScript name
`SlooshCatalogCondensed-SemiBold`. This avoids installed-font/variable-instance
collisions. Upstream copyright and license name records are retained.

UIAppFonts is declared in both Info.plist and the XcodeGen project properties.
The existing Resources source entry copies the font into the application bundle.
No runtime network dependency or additional on-screen setting is introduced.
