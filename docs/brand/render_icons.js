// Renders the ZutLib PNG icons from the SVG masters made by build_brand.py.
//
//   node docs/brand/render_icons.js            every app icon
//   node docs/brand/render_icons.js preview    only the review sheets
//
// Needs Playwright with Chromium. Writes Android, iOS and web icons in
// place, so the app picks them up on the next build.
const { chromium } = require('playwright')
const fs = require('fs')
const path = require('path')

const ROOT = path.resolve(__dirname, '..', '..')
const svg = (name) => fs.readFileSync(path.join(__dirname, name), 'utf8')

async function render(page, svgText, w, h, out, background = 'transparent') {
  await page.setViewportSize({ width: w, height: h })
  await page.setContent(
    `<html><body style="margin:0;background:${background}">` +
      svgText.replace('<svg ', `<svg style="display:block;width:${w}px;height:${h}px" `) +
      '</body></html>')
  await page.screenshot({ path: out, omitBackground: background === 'transparent', clip: { x: 0, y: 0, width: w, height: h } })
  console.log('rendered', path.relative(ROOT, out))
}

;(async () => {
  const browser = await chromium.launch()
  const page = await browser.newPage({ deviceScaleFactor: 1 })
  const preview = process.argv[2] === 'preview'
  const out = (p) => path.join(ROOT, p)

  if (preview) {
    const dir = process.argv[3] || __dirname
    await render(page, svg('refinement-before-after.svg'), 840, 700, path.join(dir, 'refinement-before-after.png'))
    const lockup = svg('zutlib-lockup.svg')
    const m = /viewBox="([-\d. ]+)"/.exec(lockup)[1].split(' ').map(Number)
    await render(page, lockup, Math.round(m[2] * 2), Math.round(m[3] * 2), path.join(dir, 'lockup-preview.png'), '#F6F9FD')
    await browser.close()
    return
  }

  const icon = svg('zutlib-app-icon.svg')
  const maskable = svg('zutlib-maskable.svg')
  const fav = svg('favicon.svg')

  // Android legacy launcher icons (Android 7 and older).
  for (const [dir, px] of [['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192]]) {
    await render(page, icon, px, px, out(`android/app/src/main/res/mipmap-${dir}/ic_launcher.png`))
  }

  // iOS: every size listed in Contents.json, on a solid tile (no alpha).
  const iosDir = out('ios/Runner/Assets.xcassets/AppIcon.appiconset')
  const contents = JSON.parse(fs.readFileSync(path.join(iosDir, 'Contents.json'), 'utf8'))
  const square = icon.replace(/rx="[\d.]+"/, 'rx="0"')
  for (const im of contents.images) {
    if (!im.filename) continue
    const pt = parseFloat(im.size.split('x')[0])
    const px = Math.round(pt * parseInt(im.scale))
    await render(page, square, px, px, path.join(iosDir, im.filename), '#1D5FC4')
  }

  // Web: favicon, PWA icons and maskable icons.
  await render(page, fav, 64, 64, out('web/favicon.png'))
  await render(page, icon, 192, 192, out('web/icons/Icon-192.png'))
  await render(page, icon, 512, 512, out('web/icons/Icon-512.png'))
  await render(page, maskable, 192, 192, out('web/icons/Icon-maskable-192.png'), '#1D5FC4')
  await render(page, maskable, 512, 512, out('web/icons/Icon-maskable-512.png'), '#1D5FC4')

  // Splash marks (Android 11 and older; light and dark).
  const markOnly = svg('zutlib-symbol.svg')
  const markDark = svg('zutlib-symbol-reversed.svg')
  for (const [dir, px] of [['mdpi', 128], ['hdpi', 192], ['xhdpi', 256], ['xxhdpi', 384], ['xxxhdpi', 512]]) {
    await render(page, markOnly, px, px, out(`android/app/src/main/res/drawable-${dir}/splash_mark.png`))
    await render(page, markDark, px, px, out(`android/app/src/main/res/drawable-night-${dir}/splash_mark.png`))
  }
  // iOS launch screen: the mark 96 pt tall, light and dark.
  const launch = path.join(iosDir, '..', 'LaunchImage.imageset')
  for (const [suffix, k] of [['', 1], ['@2x', 2], ['@3x', 3]]) {
    await render(page, markOnly, 96 * k, 96 * k, path.join(launch, `LaunchImage${suffix}.png`))
    await render(page, markDark, 96 * k, 96 * k, path.join(launch, `LaunchImageDark${suffix}.png`))
  }
  await browser.close()
})()
