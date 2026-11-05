// Canonical vector -> launcher icons + Settings previews. No redrawing/typeface substitution.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');
const { Resvg } = require('@resvg/resvg-js');

const assets = path.resolve(__dirname, '../../sloosh-iOS/sloosh/Resources/Assets.xcassets');
const check = process.argv.includes('--check');
const layouts = [
  { name: 'AppIcon', preview: 'Default', width: 780, centerY: 512, clean: [120, 410, 904, 614] },
  { name: 'AppIcon-Cinema', preview: 'Cinema', width: 680, centerY: 378, clean: [169, 291, 854, 467] },
];
const colors = { light: '#000000', dark: '#93f300', tinted: '#ffffff' };

async function output(relative, png) {
  const file = path.join(assets, relative);
  if (check) {
    const stored = await fs.readFile(file);
    const metadata = await sharp(stored).metadata();
    assert.equal(metadata.width, 1024, `${relative}: width`);
    assert.equal(metadata.height, 1024, `${relative}: height`);
    assert.equal(metadata.hasAlpha, false, `${relative}: launcher artwork must be opaque`);
    assert((await sharp(stored).raw().toBuffer()).equals(await sharp(png).raw().toBuffer()),
      `${relative}: out of sync with LogoText; run npm run generate in tools/branding`);
  } else {
    await fs.writeFile(file, png);
  }
  console.log(`${check ? 'PASS' : 'Updated'} ${relative}`);
}

async function main() {
  const svg = await fs.readFile(path.join(assets, 'LogoText.imageset/sloosh.svg'), 'utf8');
  const viewBox = svg.match(/viewBox="0 0 ([\d.]+) ([\d.]+)"/);
  assert(viewBox, 'Canonical SVG must declare its aspect ratio');
  for (const layout of layouts) {
    const contents = JSON.parse((await fs.readFile(path.join(assets, `${layout.name}.appiconset/Contents.json`), 'utf8')).replace(/^\uFEFF/, ''));
    assert.deepEqual(contents.images.map(x => x.filename).sort(), ['dark.png', 'light.png', 'tinted.png']);
    for (const [mode, color] of Object.entries(colors)) {
      const background = await fs.readFile(path.join(__dirname, 'backgrounds', `${layout.name}-${mode}.png`));
      const [x0, y0, x1, y1] = layout.clean;
      const patch = await sharp(background).extract({ left: x0, top: y0, width: x1 - x0, height: y1 - y0 }).raw().toBuffer();
      for (let i = 0; i < patch.length; i += 3) {
        assert(mode === 'light' ? patch[i + 1] >= 253 : mode === 'tinted' ? patch[i] + patch[i + 1] + patch[i + 2] === 0 : patch[i] === patch[i + 1] && patch[i] === patch[i + 2],
          `${layout.name}-${mode}: background layer must not contain old lettering`);
      }
      const height = Math.round(layout.width * Number(viewBox[2]) / Number(viewBox[1]));
      const colored = svg.replace(/fill="#[0-9a-f]+"/gi, `fill="${color}"`);
      const raster = new Resvg(colored, { fitTo: { mode: 'width', value: layout.width * 4 } }).render().asPng();
      const lettering = await sharp(raster).resize(layout.width, height).png().toBuffer();
      const png = await sharp(background).composite([{
        input: lettering, left: Math.round((1024 - layout.width) / 2), top: Math.round(layout.centerY - height / 2),
      }]).removeAlpha().png().toBuffer();
      await output(`${layout.name}.appiconset/${mode}.png`, png);
      if (mode === 'light') await output(`AppIconPreview-${layout.preview}.imageset/icon.png`, png);
    }
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
