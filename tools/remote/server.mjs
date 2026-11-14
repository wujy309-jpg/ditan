#!/usr/bin/env node
/**
 * 碳迹 —— 手机远程控制台（零依赖）
 *
 * 把 Mac 上 HarmonyOS 模拟器里运行的应用，投到手机浏览器上，并接受触摸。
 * 手机不需要装任何东西 —— OPPO / 小米 / iPhone 都行，这是网页。
 *
 * 链路：
 *   手机浏览器 ──HTTP/WS──► 本服务 (0.0.0.0:8899)
 *                              │ hdc shell snapshot_display -w 660 -h 1116
 *                              │ hdc file recv  ← 一帧 JPEG（约 56 KB / 120 ms）
 *                              ▼
 *                           HarmonyOS 模拟器（碳迹运行中）
 *
 * 反向：手机的点击 → 归一化坐标 → ×(1320,2232) → hdc shell uinput -T -c
 *
 * 为什么用「截图 + 注入」而不是 scrcpy：
 *   模拟器走的是 hdc（华为调试桥），不是 adb，scrcpy 接不上。
 *
 * 用法：
 *   node tools/remote/server.mjs                 # 默认 0.0.0.0:8899，自动生成令牌
 *   node tools/remote/server.mjs --port 9000
 *   node tools/remote/server.mjs --fps 10 --width 720
 *   node tools/remote/server.mjs --no-token      # 仅本机调试方便，别在公共网络用
 */
import http from 'node:http'
import crypto from 'node:crypto'
import { execFile as execFileCb } from 'node:child_process'
import { promisify } from 'node:util'
import { readFile, access, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { tmpdir, networkInterfaces } from 'node:os'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import zlib from 'node:zlib'

const pexec = promisify(execFileCb)
const execFile = execFileCb
const HERE = path.dirname(fileURLToPath(import.meta.url))

// --- 参数 -------------------------------------------------------------------
const argv = process.argv.slice(2)
const flag = (name, dflt) => {
  const i = argv.indexOf(`--${name}`)
  if (i === -1) return dflt
  const v = argv[i + 1]
  return v && !v.startsWith('--') ? v : true
}
const PORT = Number(flag('port', 8899))
const HOST = String(flag('host', '0.0.0.0'))
const FPS = Math.max(1, Math.min(24, Number(flag('fps', 18))))
const CAP_W = Number(flag('width', 660))
const CAP_H = Math.round((CAP_W * 2232) / 1320) // 保持模拟器 1320×2232 的 9:19.5 比例
const DEV_W = 1320 // 注入坐标用的真实分辨率
const DEV_H = 2232
const MODE = String(flag('mode', 'loop')) // loop = 设备端循环（快）；shot = 单次抓帧（稳）
const USE_TOKEN = !argv.includes('--no-token')
const FIXED_TOKEN = typeof flag('token', '') === 'string' ? String(flag('token', '')) : ''
const TOKEN = USE_TOKEN ? (FIXED_TOKEN || crypto.randomBytes(9).toString('base64url')) : ''

// 五个页签在设备上的坐标（与 tools/preview.sh 实测一致）
const TABS = [
  { name: '记一笔', x: 132 },
  { name: '看板', x: 396 },
  { name: '积分', x: 660 },
  { name: '科普', x: 924 },
  { name: '我的', x: 1188 },
]
const TAB_Y = 2075

// --- hdc 定位 ---------------------------------------------------------------
async function findHdc() {
  const cands = []
  if (process.env.HDC_PATH) cands.push(process.env.HDC_PATH)
  const roots = [
    process.env.DEVECO_HOME,
    '/Applications/DevEco-Studio.app',
    '/Applications/DevEco-Studio.app/Contents',
    path.join(process.env.HOME ?? '', 'DevEco-Studio'),
  ].filter(Boolean)
  for (const r of roots) {
    cands.push(path.join(r, 'Contents/sdk/default/openharmony/toolchains/hdc'))
    cands.push(path.join(r, 'sdk/default/openharmony/toolchains/hdc'))
  }
  for (const c of cands) {
    try {
      await access(c)
      return c
    } catch {}
  }
  throw new Error(
    '找不到 hdc。用 HDC_PATH=/path/to/hdc 指定，或设置 DEVECO_HOME 指向 DevEco Studio。',
  )
}

let HDC = null
const REMOTE_SHOT = '/data/local/tmp/carbon-live.jpeg'
const LOCAL_SHOT = path.join(tmpdir(), 'carbon-live.jpeg')

// 手机拍的照片：电脑转成 JPEG 后推到模拟器这个固定路径，应用自己读它
const PHONE_PHOTO_PATH = '/data/local/tmp/carbon-phone.jpg'

// 设备端常驻抓帧循环：把「每帧一次进程」变成「设备端连续抓 + 主机只拉最新」
const DEVICE_LOOP_SH = '/data/local/tmp/carbon-loop.sh'
const DEVICE_LOOP_PID = '/data/local/tmp/carbon-loop.pid'
const DEVICE_LOOP_STOP = '/data/local/tmp/carbon-loop.stop'
const DEVICE_FRAME = '/data/local/tmp/carbon-live.jpeg'  // 注意：snapshot_display 只认 .jpeg
const LOCAL_FRAME = path.join(tmpdir(), 'carbon-live.jpeg')
const LOCAL_PHONE = path.join(tmpdir(), 'carbon-phone.jpg')
const UPLOAD_MAX = 16 * 1024 * 1024

// 电脑摄像头：用 macOS 的 avfoundation 抓一帧（ffmpeg 已装）
const FFMPEG = (() => {
  const cands = [
    process.env.FFMPEG_PATH,
    '/opt/homebrew/bin/ffmpeg',
    '/usr/local/bin/ffmpeg',
    '/usr/bin/ffmpeg',
  ].filter(Boolean)
  for (const c of cands) {
    try {
      if (existsSync(c)) return c
    } catch {}
  }
  return null
})()
const WEBCAM_INDEX = String(flag('webcam', '0')) // 0 = 内置摄像头

// 电脑摄像头：由 Chrome 页面（cam.html）推帧过来。
// 为什么绕 Chrome：宿主 App 没有 camera entitlement，TCC 直接拒绝且不弹窗；
// Chrome 已获授权，但必须用 LaunchServices（open -na）启动它，
// 它才是「责任进程」，否则会继承调用方身份同样被拒。
let camFrame = null          // { buf, ts }
let camWantAt = 0            // 最近一次「应用要取景」的时间
let camLaunchedAt = 0
const CAM_CHROME_DIR = path.join(tmpdir(), 'carbon-cam-profile')
const CAM_PAGE = (port) => `http://127.0.0.1:${port}/cam.html?t=${DEVICE_TOKEN}`

// 现场实拍演示图：页面上一键送达，答辩时不用翻目录找文件
const DEMO_PHOTO = String(
  flag('demo', path.join(HERE, '..', '..', '素材', '远程演示素材', '现场实拍-共享单车.jpg')),
)

// 模拟器里的应用取图用的固定令牌（应用里硬编码同一个值）。
// 注意：它只换得到「最近一张手机照片」，换不到 GUI 控制权。
const DEVICE_TOKEN = String(flag('device-token', 'carbon-dev'))

// --- 单通道队列：hdc 不适合并发调用，串行排队 ---------------------------------
let chain = Promise.resolve()
function serial(fn) {
  const run = chain.then(fn, fn)
  chain = run.then(
    () => {},
    () => {},
  )
  return run
}

let deviceOnline = false
let lastError = ''

async function sh(cmd, args) {
  const { stdout } = await pexec(HDC, [cmd, ...args], {
    timeout: 15_000,
    maxBuffer: 4 * 1024 * 1024,
  })
  return stdout
}

// --- 截图 -------------------------------------------------------------------
let captureMs = 0

/** 单次调用抓帧（安全兜底）：设备端截图 + base64 在同一条 hdc 通道回传 */
async function grabFrameOnce() {
  const t0 = Date.now()
  const { stdout } = await pexec(
    HDC,
    [
      'shell',
      `snapshot_display -w ${CAP_W} -h ${CAP_H} -f ${DEVICE_FRAME}; base64 -w 0 ${DEVICE_FRAME}`,
    ],
    { timeout: 15_000, maxBuffer: 8 * 1024 * 1024, encoding: 'buffer' },
  )
  const text = stdout.toString('latin1')
  const m = text.match(/[A-Za-z0-9+/=]{4000,}/g)
  if (!m) throw new Error('没拿到画面数据')
  const buf = Buffer.from(m[m.length - 1], 'base64')
  if (buf.length < 1000 || buf[0] !== 0xff || buf[1] !== 0xd8) throw new Error('画面数据不是合法 JPEG')
  captureMs = Date.now() - t0
  return buf
}

const LOOP_SCRIPT = (w, h) => `#!/bin/sh
# 碳迹 · 设备端常驻抓帧（由 Mac 端 server.mjs 启停，用 pid 文件管理）
echo $$ > ${DEVICE_LOOP_PID}
while :; do
  [ -f ${DEVICE_LOOP_STOP} ] && break
  snapshot_display -w ${w} -h ${h} -f /data/local/tmp/carbon-ct.jpeg 2>/dev/null
  mv /data/local/tmp/carbon-ct.jpeg ${DEVICE_FRAME} 2>/dev/null
done
rm -f ${DEVICE_LOOP_PID}
`

let deviceLoopOn = false

async function readLoopPid() {
  try {
    const out = (await sh('shell', [`cat ${DEVICE_LOOP_PID} 2>/dev/null`])).trim()
    return out ? Number(out) : 0
  } catch {
    return 0
  }
}

async function pidAlive(pid) {
  if (!pid) return false
  try {
    const out = (await sh('shell', [`kill -0 ${pid} 2>/dev/null && echo alive || echo dead`])).trim()
    return out.includes('alive')
  } catch {
    return false
  }
}

/** 起设备端循环（幂等）。失败返回 false，调用方回退到单次抓帧 */
async function ensureDeviceLoop() {
  if (deviceLoopOn) {
    const pid = await readLoopPid()
    if (await pidAlive(pid)) return true
    deviceLoopOn = false
  }
  try {
    const scriptPath = path.join(tmpdir(), 'carbon-loop.sh')
    await writeFile(scriptPath, LOOP_SCRIPT(CAP_W, CAP_H))
    await sh('file', ['send', scriptPath, DEVICE_LOOP_SH])
    // 注意：这里绝对不能用 `pkill -f <脚本名>` —— 这条命令自身的命令行也含那个字符串，
    // pkill 会把执行它的 shell 一起杀掉，导致后面的 nohup 永远执行不到
    // （表现出来的现象就是：进程号看着变了，但画面永远不更新）。
    await sh('shell', [
      `rm -f ${DEVICE_LOOP_STOP} ${DEVICE_LOOP_PID}; chmod +x ${DEVICE_LOOP_SH}; ` +
        `nohup ${DEVICE_LOOP_SH} >/dev/null 2>&1 &`,
    ])
    await new Promise((r) => setTimeout(r, 600))
    const pid = await readLoopPid()
    deviceLoopOn = await pidAlive(pid)
    console.log(
      deviceLoopOn ? `[loop] 设备端抓帧循环已启动 pid=${pid}` : '[loop] 启动失败，回退单次抓帧',
    )
    return deviceLoopOn
  } catch (e) {
    console.log(`[loop] 启动异常，回退单次抓帧: ${String(e?.message ?? e).slice(0, 120)}`)
    deviceLoopOn = false
    return false
  }
}

/** 停设备端循环（没有客户端时省 CPU） */
async function stopDeviceLoop() {
  if (!deviceLoopOn) return
  deviceLoopOn = false
  try {
    const pid = await readLoopPid()
    if (pid) await sh('shell', [`touch ${DEVICE_LOOP_STOP}; kill ${pid} 2>/dev/null; true`])
    await new Promise((r) => setTimeout(r, 200))
    await sh('shell', [`rm -f ${DEVICE_LOOP_STOP} ${DEVICE_LOOP_PID}`])
    console.log('[loop] 设备端抓帧循环已停止')
  } catch {}
}

/** 从设备端循环拉最新一帧（只有一次 hdc 调用） */
async function grabFrameLoop() {
  const t0 = Date.now()
  await sh('file', ['recv', DEVICE_FRAME, LOCAL_FRAME])
  const buf = await readFile(LOCAL_FRAME)
  if (buf.length < 1000 || buf[0] !== 0xff || buf[1] !== 0xd8) throw new Error('拉到的不是合法 JPEG')
  captureMs = Date.now() - t0
  return buf
}

async function grabFrame() {
  if (MODE === 'loop') {
    if (await ensureDeviceLoop()) {
      try {
        return await grabFrameLoop()
      } catch (e) {
        // 循环挂了就退回单次抓帧，别让画面断掉
        console.log(`[loop] 拉帧失败，改用单次抓帧: ${String(e?.message ?? e).slice(0, 100)}`)
        deviceLoopOn = false
      }
    }
  }
  return grabFrameOnce()
}

/**
 * 把一张图片送到模拟器的固定落点：转 JPEG → hdc 推送。
 * /upload（手机拍的）和 /demo（预设演示图）共用同一条路径，
 * 保证两条路在应用看来完全一样。
 */
async function deliverToEmulator(buf) {
  const raw = path.join(tmpdir(), 'carbon-upload.raw')
  await writeFile(raw, buf)
  await pexec('/usr/bin/sips', ['-s', 'format', 'jpeg', '-Z', '1280', raw, '--out', LOCAL_PHONE], {
    timeout: 20_000,
  })
  const info = await readFile(LOCAL_PHONE)
  await sh('file', ['send', LOCAL_PHONE, PHONE_PHOTO_PATH])
  return info.length
}

// --- 输入注入 ---------------------------------------------------------------
async function tap(nx, ny) {
  const x = Math.round(nx * DEV_W)
  const y = Math.round(ny * DEV_H)
  await sh('shell', ['uinput', '-T', '-c', String(x), String(y)])
  return { x, y }
}

/**
 * 滑动（滚动 / 拖动）。
 *
 * 用 `-T -m`（平滑移动）而不是 `-T -g`（拖拽）：后者要求「先按压 ≥500ms 再移动」，
 * 体感上像是先长按再拖，滑动手感很差；`-m` 就是原生滑动手势。
 *
 * 命令形如：uinput -T -m <x1> <y1> <x2> <y2> <平滑时长ms>
 * （早期版本只给了一个时间参数，uinput 直接报 "wrong number of parameters"
 *   并静默什么都不做 —— 这正是手机滑不动的原因。）
 */
async function drag(nx1, ny1, nx2, ny2, ms = 300) {
  const p = [nx1, ny1, nx2, ny2].map((n, i) =>
    String(Math.round(n * (i % 2 === 0 ? DEV_W : DEV_H))),
  )
  // 平滑时长跟随真实手势快慢，夹在 [120, 700]
  const smooth = Math.max(120, Math.min(700, Math.round(ms)))
  await sh('shell', ['uinput', '-T', '-m', ...p, String(smooth)])
}

/** 切到第 i 个页签（坐标与 tools/preview.sh 实测一致） */
async function tab(i) {
  const t = TABS[i]
  if (!t) return
  await sh('shell', ['uinput', '-T', '-c', String(t.x), String(TAB_Y)])
}

/** 系统返回键（KEYCODE_BACK = 2） */
async function back() {
  await sh('shell', ['uinput', '-K', '-d', '2'])
  await sh('shell', ['uinput', '-K', '-u', '2'])
}

// --- WebSocket：手写最小实现（服务端只需要二进制下发 + 文本上行） --------------
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

function wsAccept(key) {
  return crypto.createHash('sha1').update(key + WS_GUID).digest('base64')
}

function wsFrame(opcode, payload) {
  const len = payload.length
  let head
  if (len < 126) {
    head = Buffer.allocUnsafe(2)
    head[1] = len
  } else if (len < 65536) {
    head = Buffer.allocUnsafe(4)
    head[1] = 126
    head.writeUInt16BE(len, 2)
  } else {
    head = Buffer.allocUnsafe(10)
    head[1] = 127
    head.writeBigUInt64BE(BigInt(len), 2)
  }
  head[0] = 0x80 | opcode
  return Buffer.concat([head, payload])
}

/** 解析客户端帧（浏览器发的帧一定带 mask） */
function parseFrames(buf, onMessage) {
  let off = 0
  while (off + 2 <= buf.length) {
    const b0 = buf[off]
    const b1 = buf[off + 1]
    const opcode = b0 & 0x0f
    const masked = (b1 & 0x80) !== 0
    let len = b1 & 0x7f
    let p = off + 2
    if (len === 126) {
      if (p + 2 > buf.length) break
      len = buf.readUInt16BE(p)
      p += 2
    } else if (len === 127) {
      if (p + 8 > buf.length) break
      len = Number(buf.readBigUInt64BE(p))
      p += 8
    }
    const maskLen = masked ? 4 : 0
    if (p + maskLen + len > buf.length) break
    let payload = buf.subarray(p + maskLen, p + maskLen + len)
    if (masked) {
      const mask = buf.subarray(p, p + 4)
      payload = Buffer.from(payload)
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3]
    }
    off = p + maskLen + len
    if (opcode === 0x8) return { closed: true }
    if (opcode === 0x1 || opcode === 0x2) {
      onMessage(opcode, payload)
    }
  }
  return { rest: buf.subarray(off) }
}

// --- 帧广播 -----------------------------------------------------------------
const clients = new Set()
let lastHash = ''
let lastFrame = null // 记住最近一帧：新客户端连上立刻补发，否则静态画面会看到空白
let framesSent = 0
let fpsWindow = []

function broadcast(buf) {
  // 静态画面不重复发：省带宽，也省手机电量
  const h = crypto.createHash('md5').update(buf).digest('base64')
  if (h === lastHash) return
  lastHash = h
  lastFrame = buf
  const frame = wsFrame(0x2, buf)
  for (const c of clients) {
    if (c.socket.writable) c.socket.write(frame)
  }
  framesSent++
  const now = Date.now()
  fpsWindow.push(now)
  fpsWindow = fpsWindow.filter((t) => now - t < 3000)
}

/** 新客户端补发当前画面 */
function sendLastFrame(client) {
  if (!lastFrame || !client.socket.writable) return
  client.socket.write(wsFrame(0x2, lastFrame))
}

let looping = false
async function loop() {
  if (looping) return
  looping = true
  const period = Math.round(1000 / FPS)
  const tick = async () => {
    if (clients.size === 0) {
      looping = false
      return
    }
    const t0 = Date.now()
    try {
      const buf = await serial(grabFrame)
      deviceOnline = true
      lastError = ''
      broadcast(buf)
    } catch (e) {
      deviceOnline = false
      lastError = String(e?.message ?? e).split('\n')[0].slice(0, 200)
    }
    const spent = Date.now() - t0
    setTimeout(tick, Math.max(0, period - spent))
  }
  tick()
}

// --- HTTP -------------------------------------------------------------------
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
}

function authOk(url) {
  if (!USE_TOKEN) return true
  const t = url.searchParams.get('t')
  return t === TOKEN
}

function logAccess(req, extra = '') {
  const ip = (req.socket.remoteAddress ?? '?').replace(/^::ffff:/, '')
  const t = new Date().toISOString().slice(11, 19)
  console.log(`[${t}] ${ip} ${req.method} ${req.url ?? ''} ${extra}`)
}

const server = http.createServer(async (req, res) => {
  logAccess(req)
  const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`)

  // 手机上传照片 → 转 JPEG → 推到模拟器 → 应用点「手机取图」就能读到
  if (url.pathname === '/upload' && req.method === 'POST') {
    if (!authOk(url)) {
      res.writeHead(403)
      res.end('bad token')
      return
    }
    const chunks = []
    let size = 0
    let aborted = false
    req.on('data', (c) => {
      size += c.length
      if (size > UPLOAD_MAX) {
        aborted = true
        req.destroy()
        return
      }
      chunks.push(c)
    })
    req.on('end', async () => {
      if (aborted) return
      try {
        const sent = await deliverToEmulator(Buffer.concat(chunks))
        console.log(`[photo] 收到手机照片 ${size} 字节 → 已推送到模拟器（${sent} 字节）`)
        res.writeHead(200, { 'content-type': 'application/json' })
        res.end(JSON.stringify({ ok: true, received: size, sent }))
      } catch (e) {
        lastError = String(e?.message ?? e).slice(0, 200)
        console.log(`[photo] 失败: ${lastError}`)
        res.writeHead(500, { 'content-type': 'application/json' })
        res.end(JSON.stringify({ ok: false, error: lastError }))
      }
    })
    return
  }

  // 一键送达预设演示图（答辩时点一下就行）
  if (url.pathname === '/demo' && req.method === 'POST') {
    if (!authOk(url)) {
      res.writeHead(403)
      res.end('bad token')
      return
    }
    try {
      const buf = await readFile(DEMO_PHOTO)
      const sent = await deliverToEmulator(buf)
      console.log(`[demo] 预设演示图已送达（${sent} 字节）`)
      res.writeHead(200, { 'content-type': 'application/json' })
      res.end(JSON.stringify({ ok: true, sent }))
    } catch (e) {
      lastError = String(e?.message ?? e).slice(0, 200)
      console.log(`[demo] 失败: ${lastError}`)
      res.writeHead(500, { 'content-type': 'application/json' })
      res.end(JSON.stringify({ ok: false, error: lastError }))
    }
    return
  }

  // 应用取图端点：模拟器通过 QEMU 网关 10.0.2.2 访问这里
  if (url.pathname === '/latest.jpg') {
    if (url.searchParams.get('t') !== DEVICE_TOKEN) {
      res.writeHead(403)
      res.end('bad device token')
      return
    }
    try {
      const img = await readFile(LOCAL_PHONE)
      res.writeHead(200, { 'content-type': 'image/jpeg', 'cache-control': 'no-store' })
      res.end(img)
    } catch {
      res.writeHead(404, { 'content-type': 'text/plain' })
      res.end('还没有手机照片')
    }
    return
  }

  // ── 电脑摄像头：三个端点 ───────────────────────────────────────────
  // Chrome 页面轮询「要不要画面」
  if (url.pathname === '/webcam/want') {
    if (url.searchParams.get('t') !== DEVICE_TOKEN) { res.writeHead(403); res.end('bad token'); return }
    res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
    res.end(JSON.stringify({ want: Date.now() - camWantAt < 20000 }))
    return
  }

  // Chrome 页面把一帧推过来（内存保存，不落盘）
  if (url.pathname === '/webcam/frame' && req.method === 'POST') {
    if (url.searchParams.get('t') !== DEVICE_TOKEN) { res.writeHead(403); res.end('bad token'); return }
    const chunks = []
    let size = 0
    req.on('data', (c) => { size += c.length; if (size <= 8 * 1024 * 1024) chunks.push(c) })
    req.on('end', () => {
      const buf = Buffer.concat(chunks)
      if (buf.length > 1000 && buf[0] === 0xff && buf[1] === 0xd8) {
        camFrame = { buf, ts: Date.now() }
      }
      res.writeHead(200, { 'content-type': 'application/json' })
      res.end(JSON.stringify({ ok: true }))
    })
    return
  }

  // 应用取图：请求一帧新鲜的电脑摄像头画面
  if (url.pathname === '/capture.jpg') {
    if (url.searchParams.get('t') !== DEVICE_TOKEN) { res.writeHead(403); res.end('bad token'); return }
    camWantAt = Date.now()
    const askedAt = camWantAt

    // 没有活跃的 Chrome 取景页就拉起来（LaunchServices 启动才有相机权限）
    const freshNow = camFrame && Date.now() - camFrame.ts < 5000
    if (!freshNow && Date.now() - camLaunchedAt > 30000) {
      camLaunchedAt = Date.now()
      try {
        await pexec('/usr/bin/open', [
          '-na', 'Google Chrome', '--args',
          `--user-data-dir=${CAM_CHROME_DIR}`,
          '--no-first-run', '--no-default-browser-check',
          '--use-fake-ui-for-media-stream',
          CAM_PAGE(PORT),
        ])
        console.log('[webcam] 已用 LaunchServices 拉起 Chrome 取景页')
      } catch (e) {
        console.log(`[webcam] 拉起 Chrome 失败: ${String(e?.message ?? e).slice(0, 120)}`)
      }
    }

    // 等一帧比「请求时刻」更新的画面
    const deadline = Date.now() + 9000
    while (Date.now() < deadline) {
      if (camFrame && camFrame.ts >= askedAt && Date.now() - camFrame.ts < 3000) {
        console.log(`[webcam] 取帧成功 ${camFrame.buf.length} 字节`)
        res.writeHead(200, { 'content-type': 'image/jpeg', 'cache-control': 'no-store' })
        res.end(camFrame.buf)
        return
      }
      await new Promise((r) => setTimeout(r, 120))
    }

    const hint = camFrame
      ? '电脑摄像头画面已过期 —— 让 Chrome 的「碳迹 · 电脑摄像头」窗口保持打开'
      : '电脑摄像头还没连上 —— 请保持 Chrome 取景窗口打开（已尝试自动打开）'
    lastError = hint
    console.log(`[webcam] ${hint}`)
    res.writeHead(503, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ ok: false, error: hint }))
    return
  }

  if (url.pathname === '/healthz') {
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end(
      JSON.stringify({
        ok: true,
        deviceOnline,
        lastError,
        captureMs,
        assetVersion: ASSET_VERSION,
        clients: clients.size,
        fps: fpsWindow.length / 3,
        framesSent,
      }),
    )
    return
  }

  // 取景页由 Chrome 打开，用设备令牌即可（只暴露页面本身，不含控制能力）
  const isCamPage = url.pathname === '/cam.html' && url.searchParams.get('t') === DEVICE_TOKEN
  if (!authOk(url) && !isCamPage) {
    res.writeHead(403, { 'content-type': 'text/plain; charset=utf-8' })
    res.end('需要令牌：请用启动时打印的完整链接访问。')
    return
  }

  let file = url.pathname === '/' ? 'page.html' : url.pathname.replace(/^\/+/, '')
  if (file.includes('..')) {
    res.writeHead(400)
    res.end('bad path')
    return
  }
  try {
    const data = await readFile(path.join(HERE, file))
    res.writeHead(200, {
      'content-type': MIME[path.extname(file)] ?? 'application/octet-stream',
      // 投屏页面每次加载都要新的，别缓存
      'cache-control': 'no-store',
    })
    res.end(data)
  } catch {
    res.writeHead(404)
    res.end('not found')
  }
})

/**
 * WebSocket 握手。注意：upgrade 请求不会进 request 处理器，
 * 必须挂在 server 的 'upgrade' 事件上，且要直接写 socket（没有 res）。
 */
function handleUpgrade(req, socket, head) {
  const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`)
  if (url.pathname !== '/ws') {
    socket.end('HTTP/1.1 404 Not Found\r\n\r\n')
    return
  }
  if (!authOk(url)) {
    socket.end('HTTP/1.1 403 Forbidden\r\n\r\n')
    return
  }
  const key = req.headers['sec-websocket-key']
  if (!key) {
    socket.end('HTTP/1.1 400 Bad Request\r\n\r\n')
    return
  }
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${wsAccept(key)}\r\n\r\n`,
  )
  socket.setNoDelay(true)
  const client = { socket }
  clients.add(client)

  const feed = (chunk) => {
    const r = parseFrames(chunk, onWsMessage(client))
    return r
  }

  let buf = Buffer.alloc(0)
  if (head && head.length) buf = Buffer.concat([buf, head])

  const pump = () => {
    if (!buf.length) return
    const r = feed(buf)
    if (r.closed) return socket.destroy()
    buf = r.rest ?? Buffer.alloc(0)
  }
  pump()

  socket.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk])
    pump()
  })

  const drop = () => {
    clients.delete(client)
    if (clients.size === 0) stopDeviceLoop()
  }
  socket.on('close', drop)
  socket.on('error', drop)

  sendLastFrame(client)
  if (clients.size === 1) loop()
}

function onWsMessage(client) {
  return async (opcode, payload) => {
    if (opcode !== 0x1) return
    let msg
    try {
      msg = JSON.parse(payload.toString('utf8'))
    } catch {
      return
    }
    try {
      console.log(`[ws] 收到控制消息: ${JSON.stringify(msg)}`)
      // 注意：这里**不能**走 serial()。截图循环长期占用队列，
      // 若控制命令也排队，滑动时每 260ms 一条 drag 会把抓帧饿死（实测掉到 0.7fps）。
      // hdc 支持并发连接，各自独立进程互不阻塞。
      switch (msg.t) {
        case 'tap':
          await tap(msg.x, msg.y)
          break
        case 'drag':
          await drag(msg.x1, msg.y1, msg.x2, msg.y2, msg.ms ?? 600)
          break
        case 'tab':
          await tab(msg.i)
          break
        case 'back':
          await back()
          break
        case 'ping':
          if (client.socket.writable) {
            client.socket.write(wsFrame(0x1, Buffer.from('{"t":"pong"}')))
          }
          break
      }
    } catch (e) {
      lastError = String(e?.message ?? e).slice(0, 200)
      console.log(`[ws] 控制消息执行失败: ${lastError}`)
    }
  }
}

// --- 启动 -------------------------------------------------------------------
function lanUrls() {
  const out = []
  const q = USE_TOKEN ? `?t=${TOKEN}` : ''
  for (const [name, addrs] of Object.entries(networkInterfaces())) {
    for (const a of addrs ?? []) {
      if (a.family === 'IPv4' && !a.internal) out.push({ name, url: `http://${a.address}:${PORT}/${q}` })
    }
  }
  return out
}

// 页面脚本版本号：页面会轮询它，发现变了就自动重载，
// 避免手机上一直跑着旧 JS（这次的滑动 bug 就是这么暴露出来的）
const ASSET_VERSION = crypto
  .createHash('md5')
  .update(await readFile(path.join(HERE, 'page.html')))
  .digest('hex')
  .slice(0, 10)

HDC = await findHdc()
// 先确认设备在不在，避免手机端一直转圈
try {
  const t = (await sh('list', ['targets'])).trim()
  deviceOnline = Boolean(t) && !t.includes('[Empty]')
  if (!deviceOnline) lastError = 'hdc 没看到设备（模拟器没起来？）'
} catch (e) {
  lastError = String(e?.message ?? e).slice(0, 200)
}

// 只要有 TCP 连进来就记一笔 —— 区分「网络不通」和「请求出错」
server.on('connection', (socket) => {
  const ip = (socket.remoteAddress ?? '?').replace(/^::ffff:/, '')
  if (ip === '127.0.0.1' || ip === '::1') return
  console.log(`[conn] ${new Date().toISOString().slice(11, 19)} ${ip} 建立了 TCP 连接`)
})

server.on('upgrade', (req, socket, head) => {
  try {
    handleUpgrade(req, socket, head)
  } catch (e) {
    lastError = String(e?.message ?? e).slice(0, 200)
    try {
      socket.destroy()
    } catch {}
  }
})

server.listen(PORT, HOST, () => {
  console.log('')
  console.log('  碳迹 · 手机远程控制台')
  console.log('  ────────────────────────────────────────────')
  console.log(`  hdc     : ${HDC}`)
  console.log(`  设备    : ${deviceOnline ? '在线' : '离线（' + lastError + '）'}`)
  console.log(`  画质    : ${CAP_W}×${CAP_H} @ ${FPS}fps`)
  console.log(`  抓帧    : ${MODE === 'loop' ? '设备端常驻循环（约 20fps 上限）' : '单次调用（约 10fps）'}`)
  console.log('')
  console.log('  手机浏览器打开（同一个 Wi-Fi）：')
  for (const u of lanUrls()) console.log(`    ${u.url}   ← ${u.name}`)
  console.log('')
  if (USE_TOKEN) {
    console.log(`  令牌: ${TOKEN}   （换一个：重启服务）`)
    console.log('')
  }
})
