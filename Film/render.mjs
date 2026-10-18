// Renders film.html to an mp4, one frame at a time, in headless Chrome.
//   node render.mjs                 full film → out/luud-demo.mp4
//   node render.mjs --stills 3,14   just those timestamps (seconds) → out/still-<t>.png
// Time only moves when this script says so, so every render is identical.
import { chromium } from 'playwright'
import { spawn } from 'node:child_process'
import { once } from 'node:events'
import { mkdirSync } from 'node:fs'

const fps = 30
const blurSamples = Number(process.env.BLUR_SAMPLES ?? 2)   // motion blur: screenshots averaged per frame
const scale = 2                                               // render at 2× and downscale for crisp text
const outDir = new URL('./out/', import.meta.url).pathname
mkdirSync(outDir, { recursive: true })

const browser = await chromium.launch({ args: ['--disable-threaded-animation', '--allow-file-access-from-files'] })
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: scale })
await page.goto(new URL('./film.html?render=1', import.meta.url).href)
await page.waitForFunction(() => window.film?.ready)
const duration = await page.evaluate(() => window.film.duration)
const stage = await page.$('#stage')
// High-quality JPEG encodes far faster than PNG at 4K; stills stay PNG.
const shoot = (t, type = 'jpeg') => page.evaluate((t) => window.film.seek(t), t)
  .then(() => stage.screenshot(type === 'png' ? { type } : { type, quality: 95 }))

const stillsArg = process.argv.indexOf('--stills')
if (stillsArg !== -1) {
  const times = (process.argv[stillsArg + 1] ?? '2,8,17,27,35,41,47').split(',').map(Number)
  for (const t of times) {
    const png = await shoot(t, 'png')
    await import('node:fs').then((fs) => fs.writeFileSync(`${outDir}still-${t}.png`, png))
    console.log(`still ${t}s`)
  }
  await browser.close()
  process.exit(0)
}

// Subframes are spread over half a frame (a 180° shutter) and averaged by ffmpeg's tmix,
// then one frame in every `blurSamples` is kept.
const n = Math.max(1, blurSamples)
const filters = [
  ...(n > 1 ? [`tmix=frames=${n}`, `select='eq(mod(n\\,${n})\\,${n - 1})'`, 'setpts=N/' + fps + '/TB'] : []),
  'scale=1920:1080:flags=lanczos',
]
const ffmpeg = spawn('ffmpeg', [
  '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps * n), '-i', '-',
  '-vf', filters.join(','), '-r', String(fps),
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'slow', '-movflags', '+faststart',
  `${outDir}luud-demo.mp4`,
], { stdio: ['pipe', 'inherit', 'inherit'] })

const frames = Math.ceil(duration * fps)
const started = Date.now()
for (let i = 0; i < frames; i++) {
  for (let k = 0; k < n; k++) {
    const jpeg = await shoot((i + (k / n) * 0.5) / fps)
    if (!ffmpeg.stdin.write(jpeg)) await once(ffmpeg.stdin, 'drain')
  }
  const eta = ((Date.now() - started) / (i + 1)) * (frames - i - 1) / 1000
  process.stdout.write(`\rframe ${i + 1}/${frames}  ~${Math.round(eta)}s left   `)
}
ffmpeg.stdin.end()
await once(ffmpeg, 'close')
await browser.close()
console.log(`\nwrote ${outDir}luud-demo.mp4`)
