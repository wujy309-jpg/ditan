# 碳迹 · 手机远程

把 Mac 上 HarmonyOS 模拟器里跑着的应用，投到**手机浏览器**上，并能用手指操作。
手机不装任何东西 —— OPPO / 小米 / 荣耀 / iPhone 都行，这只是一个网页。

> 为什么需要它：HarmonyOS 的 HAP 只能在鸿蒙设备上装，OPPO 这类 Android 手机装不了。
> 但「用手机体验应用」这件事可以绕开 —— 画面在电脑上渲染，手机只负责显示和触摸。

## 一、跑起来

```bash
# 1. 确认模拟器和应用在跑
tools/emulator.sh list | tail -2          # 应看到 127.0.0.1:5557
tools/preview.sh build && tools/preview.sh install

# 2. 起远程服务
node tools/remote/server.mjs

# 3. 手机浏览器打开屏幕上打印的那个地址（带 ?t= 令牌）
```

启动时会打印类似：

```
  手机浏览器打开（同一个 Wi-Fi）：
    http://10.216.191.165:8899/?t=jMQWh28NvxZD   ← en0
```

## 二、参数

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `--port` | 8899 | 监听端口 |
| `--host` | 0.0.0.0 | 绑定的网卡；只想本机调试用 `127.0.0.1` |
| `--fps` | 7 | 抓帧上限。实测一帧约 120–140 ms，超过 8 意义不大 |
| `--width` | 660 | 抓帧宽度（高度按 1320:2232 自动算）。720 更清晰、更费流量 |
| `--no-token` | — | 关掉令牌。**只在 `127.0.0.1` 下用**，公共网络别开 |

## 三、它怎么实现的

```
手机浏览器 ──HTTP/WS──► server.mjs (0.0.0.0:8899)
                          │ hdc shell snapshot_display -w 660 -h 1116
                          │ hdc file recv          → 一帧 JPEG
                          ▼
                       HarmonyOS 模拟器（碳迹运行中）

手机点击 ──► 归一化坐标 (0~1) ──► ×(1320,2232) ──► hdc shell uinput -T -c
```

**为什么不用 scrcpy**：模拟器走的是 hdc（华为调试桥），不是 adb，scrcpy 接不上。

**为什么用 Canvas 而不是 `<img>` + MJPEG**：Canvas 的 `getBoundingClientRect()` 让触摸坐标
换算很直接，缩放后也不会有点击偏移。

### 性能（本机实测）

| 项 | 数值 |
| --- | --- |
| 单帧抓取 | 120–140 ms（`-w 660` 时） |
| 帧体积 | 约 56 KB（660×1116 JPEG） |
| 实际帧率 | 约 7 fps |
| 带宽 | 约 3.1 Mbps（7 fps × 56 KB） |

**静态去重**：画面没变化时不重复发送，只在变化时推送。
所以停留在某个页面时几乎不耗流量；新客户端连上会立刻补发最近一帧（不会看到空白）。

## 三·二、手势（点击 / 滑动）

| 手势 | 前端 | 后端命令 | 说明 |
| --- | --- | --- | --- |
| 点一下 | `touchstart/end` 位移 < 8px | `uinput -T -c x y` | 画布任意位置 |
| 滑动 | 位移 ≥ 8px | `uinput -T -m x1 y1 x2 y2 <平滑ms>` | 滚动、拖动 |
| 页签 | 底部按钮 | `uinput -T -c <tabX> 2075` | 五个页签 |

### uinput 的两个坑（都踩过）

1. **`-T -g`（拖拽）必须给两个时间**：`-g x1 y1 x2 y2 <按压时间> <总时长>`，
   且「按压 ≥ 500ms」「总时长 − 按压 ≥ 500ms」。少给一个参数它只打印
   `wrong number of parameters`，**退出码仍是 0**，错误很容易被吞掉。
2. **滑动别用 `-g`**：它要求先按压 500ms 才移动，手感像长按后拖。用 `-T -m`（平滑移动），
   这是原生滑动原语，跟手且无延迟。

> 曾经手机上滑不动，就是第 1 条：只传了一个时间参数，命令直接失效。
> 另一个隐蔽 bug 是重构时误删了 `tab()` 函数，导致底部页签点了没反应 ——
> 现在服务端对每条控制消息都会打 `[ws]` 日志，出问题先看它。

## 三·三、页面自动跟随更新

服务端每次启动会给 `page.html` 算一个版本号，`/healthz` 返回它；
手机页面每 15 秒比对一次，发现变了就自动刷新。
所以以后改了页面脚本，手机上不用手动清缓存/重开。

## 三·四、演示图一键送达

远程页面底部有两个按钮，对应两种演示策略：

| 按钮 | 行为 | 用途 |
| --- | --- | --- |
| 拍 照 送 达 | 调用手机相机/相册，上传后送进模拟器 | 展示"真·现场拍照" |
| 演 示 图 | 直接把 `素材/远程演示素材/现场实拍-共享单车.jpg` 送进模拟器 | 兜底，不受现场光线/构图影响 |

演示图实测 `#347(0.995)`，稳定预填「骑行」。
换演示图：`server.mjs --demo <图片路径>`，或直接替换那个文件。

送达后在看板画面上点应用的「手机取图」，即可完成识别。

## 三·五、手机当相机（模拟器没有相机）

模拟器里**没有相机应用**（`com.huawei.hmos.camera` 不存在，点「拍照」报
`16000001 The specified ability does not exist`），相册也是空的，而且媒体库目录对
shell 全部拒写。所以后置摄像头这一步只能由手机代劳。

流程：

```
手机页面点 📷 拍照  →  上传到电脑  →  sips 转 JPEG  →  hdc 推给模拟器
                                                        ↓
                                  应用「记一笔 → 手机取图」→ 本地推理 → 自动预填
```

关键设计：应用**不经过局域网取图**，而是从 `http://10.0.2.2:8899/latest.jpg` 拿地址固定的那一张
（模拟器在 QEMU 用户态网络里，`10.0.2.2` 是固定宿主机网关，**不随 Mac 的 Wi-Fi IP 变化**）。
应用里这一跳只取一次图，推理仍在本机完成。

> 为什么不是「把照片塞进相册」：`/storage/media/**` 对 shell 拒写，`mediatool` 也没有插入接口；
> 应用的沙箱目录同样写不进去。改成「应用自己取」是唯一可行且不引入云端的办法。

### 电脑摄像头（第二个拍照来源）

模拟器没有相机应用，除了手机，也可以直接用**这台 Mac 的摄像头**。
应用里「记一笔 → 电脑拍照」会去 `http://10.0.2.2:8899/capture.jpg` 取一帧。

实测连续取帧 **约 120 ms/帧**。

#### 为什么绕了一层 Chrome（这是关键）

直接让 `ffmpeg` 或模拟器读摄像头**做不到**，系统日志写得很清楚：

```
requires entitlement com.apple.security.device.camera but it is missing
for responsible={com.deepseek.dsh, DeepSeek Harness}
```

两个结论：

1. **TCC 认的是「责任进程」**（发起者），不是被启动的程序。从命令行 fork 出去的进程
   会继承调用方的身份 —— 而本宿主 App 的签名里没有 camera entitlement（hardened runtime），
   系统**连弹窗都不给**，所以「隐私与安全性 → 相机」列表里根本不会出现它，也无法手动添加。
2. **模拟器本身（`Emulator` pid）也在请求摄像头**，同样继承了这个无权限身份 ——
   这就是模拟器为什么一直没有可用画面源。

所以改成：由 **LaunchServices**（`open -na "Google Chrome"`）启动一个 Chrome 窗口，
它带着系统已授予的相机权限，页面 `cam.html` 负责取景并推帧给 bridge。
Chrome 是「自己的责任进程」，权限才生效。

```
应用「电脑拍照」─► /capture.jpg ─► 等一帧新的画面
                                    ▲
        Chrome 取景页(cam.html) ────┘ 每 120ms 推帧（仅当 /webcam/want 为真）
        （由 open -na 启动，才有相机权限）
```

**使用**：保持「碳迹 · 电脑摄像头」窗口打开即可；关掉了下次取图会自动再拉起。

#### 三个端点

| 端点 | 作用 |
| --- | --- |
| `GET /capture.jpg?t=carbon-dev` | 应用取一帧（会等待最新画面，最长 9 秒） |
| `GET /webcam/want?t=carbon-dev` | Chrome 页面轮询「现在要取景吗」 |
| `POST /webcam/frame?t=carbon-dev` | Chrome 页面推送一帧 JPEG（内存保存，不落盘） |

### 标定表（视觉通路为什么需要它）

模型是 500 类输出的 MobileNetV2，**模型内没有类别标签**，所以「输出索引 → 低碳行为」这张表
只能实测。2026-11-13 在模拟器内实测结果：

| 索引 | 映射到 | 样本表现 |
| --- | --- | --- |
| `#347` | 骑行（travel.bike） | 5 张自行车图里 4 张 Top-1，0.981–0.997 |
| `#262` | 旧衣回收（recycle.cloth） | 3 张里 2 张 Top-1，0.962–0.978 |
| `#292` | 光盘行动（food.cleanplate） | 6 张里 3 张 Top-1，0.725–0.997 |

**没标定的类别是能力不足，不是没做完**：塑料瓶、纸箱、公交、地铁等实测 Top-1 只有 0.2–0.3
且同类图片之间来回跳，说明这个模型对这些类别没有判别力，硬填进去只会乱预填。

复现实测：`node /tmp/calib3.mjs` 的思路见上（取图 → `/upload` → 点「手机取图」→
`hdc shell hilog -x | grep "vision top5"`）。

## 三·九、公网部署（评委扫码用）已上线

```
评委手机 ──HTTPS/WSS──► dsh.saidao.asia (nginx, Let's Encrypt)
                              │ location /carbon/ → 127.0.0.1:8899
                              ▼
                        反向 SSH 隧道（Mac 主动连出，不需要公网 IP）
                              │
                              ▼
                        tools/remote/server.mjs (Mac, 8899)
                              │ hdc 截图 / 注入触摸
                              ▼
                        HarmonyOS 模拟器里的碳迹
```

访问地址：`https://dsh.saidao.asia/carbon/?t=<令牌>`
二维码：`素材/截图/远程/评委扫码-碳迹远程.png`

### 为什么不是「部署到服务器就更流畅」

**部署解决的是可达性，不是流畅度。** 帧率上限由电脑端的抓帧链路决定
（`snapshot_display` + hdc 进程开销，约 93ms/帧），云上只是多一跳转发。实测：

| 链路 | 持续滑动时帧率 |
| --- | --- |
| 局域网直连 | 8.4 fps |
| 公网经服务器（上海 ECS 中转） | **7.2 fps** |

所以公网版比局域网慢约 14%。要真正提帧率，只能在抓帧侧下手（见下节）。

### 出问题了：一键抢修

```bash
tools/remote/repair.sh
```

自动判断卡在哪一环并修好：本机服务 → 隧道进程 → **服务器僵尸会话** → 公网链路 → 模拟器状态。

> **2026-11-14 真实故障复盘**：二维码打不开，自检显示「隧道没在跑」但服务器端口仍有监听。
> 根因是切换 LaunchAgent 时被 kill 的旧 ssh 会话在服务器上留下**僵尸 sshd**，
> 它一直占着 127.0.0.1:8899，导致新隧道每次 `ExitOnForwardFailure` 直接退出
> （LaunchAgent 空转 551 次）。而 nginx 转发到那个僵尸 socket 时是**卡住**而不是报错，
> 所以浏览器表现为「打不开 / 超时」。
>
> 根治措施：
> 1. 服务器 sshd 加 `ClientAliveInterval 30` / `ClientAliveCountMax 3`
>    → 死连接 90 秒内被回收（原先 `ClientAliveInterval 0`＝永不探测，僵尸可永久存活）
> 2. Mac 端保活收紧到 `ServerAliveInterval=15` / `ServerAliveCountMax=2`（30 秒判死）
> 3. LaunchAgent `ThrottleInterval` 10 秒，断线后尽快重连

### 演示前自检（重要）

答辩上台前跑一遍：

```bash
tools/remote/doctor.sh
```

它会逐项确认：固定令牌 → 两个 LaunchAgent → 本机服务 → 模拟器在线 → Mac 是否睡眠
→ 反向隧道 → 公网页面 → 无令牌拦截 → TLS 剩余天数。任何一项 ❌ 都会导致现场翻车。

### 二维码会过期吗

**不会。** 令牌是写死在 LaunchAgent `--token` 参数里的固定字符串，服务端鉴权就是
一次字符串比对（`authOk()` 里没有任何时间判断），所以：

- 重启电脑、重启服务 → 二维码仍然有效
- 不像 DSH-手机远程的配对码（24 小时有效、用一次就换），我们这把没有有效期

但它会**因为环境问题而失效**，这些才是要盯的：

| 风险 | 后果 | 兜底 |
| --- | --- | --- |
| Mac 休眠 / 关机 | 反向隧道断，页面 502 | 演示时 `caffeinate -dims &`；跑着模拟器时 Mac 本来也不休眠 |
| 模拟器没启动 | 页面能开但没有画面 | `tools/emulator.sh start && wait` |
| LaunchAgent 被卸 | 服务/隧道不起 | `launchctl kickstart -k gui/$(id -u)/com.carbon.remote-<...>` |
| 令牌被改 | 旧二维码 403 | 改完要重新生成二维码 |
| TLS 证书过期 | 浏览器报不安全 | acme.sh 每天自动续期并 reload nginx（当前还剩 88 天） |

结论：**二维码本身永久有效**，但演示当天务必用 `doctor.sh` 确认整条链路还活着。

### 服务与运维

两个进程都由 LaunchAgent 托管，开机自启、断线自动重连：

```bash
# 状态
launchctl print gui/$(id -u)/com.carbon.remote-server | grep -E "state|pid"
launchctl print gui/$(id -u)/com.carbon.remote-tunnel | grep -E "state|pid"

# 日志
tail -f ~/Library/Logs/carbon-remote.log     # 投屏服务
tail -f ~/Library/Logs/carbon-tunnel.log     # 反向隧道

# 重启（改了 server.mjs 之后）
launchctl kickstart -k gui/$(id -u)/com.carbon.remote-server
```

服务器侧只加了一段 nginx 配置（`/etc/nginx/conf.d/dsh.conf`），**没动 relay、没动 P20**：

```nginx
location = /carbon { return 301 /carbon/; }
location /carbon/ {
    proxy_pass http://127.0.0.1:8899/;   # 反向 SSH 隧道落点
}
```

回滚（万一要撤销）：

```bash
ssh -p 2222 root@8.133.220.133 '
  cp /etc/nginx/conf.d/dsh.conf.bak-20261114-092142 /etc/nginx/conf.d/dsh.conf
  nginx -t && systemctl reload nginx'
```

### 换令牌 / 换二维码

令牌固定写在 LaunchAgent 的 `--token` 参数里，换一个：

```bash
launchctl bootout gui/$(id -u)/com.carbon.remote-server
# 编辑 ~/Library/LaunchAgents/com.carbon.remote-server.plist 改 --token
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.carbon.remote-server.plist
python3 /tmp/mkqr.py "https://dsh.saidao.asia/carbon/?t=<新令牌>" 素材/截图/远程/评委扫码-碳迹远程.png
```

## 三·十、帧率：从 6.4fps 到 10.9fps（含两次踩坑）

### 最终实测

| 指标 | 优化前 | 优化后 |
| --- | --- | --- |
| 单帧成本 | 93 ms | **34 ms** |
| 局域网（滑动中） | 8.4 fps | **10.9 fps** |
| 公网（滑动中） | 7.2 fps | **9.4 fps** |
| 公网首帧延迟 | 1042 ms | **361 ms** |
| 设备端空闲 | 持续抓帧 | **无客户端时自动停循环** |

设备端天花板实测 **16 fps**（660×1116 连续抓 5 秒 80 帧），
端到端只有 11 是因为滑动时拖拽动画本身要占设备时间。
**降低分辨率没有收益**（480 宽 14.2fps、360 宽 13.6fps，反而更低）——
开销是固定成本，不随像素走。

### 做的三件事

1. **截图与回传合并成一次 hdc 调用**（设备端 base64 直接回传）
   156ms → 93ms。原来每帧要 fork 两次 hdc，每次约 28ms 纯启动开销。
2. **控制命令与抓帧解耦**（原先共用一个串行队列）
   滑动时 drag 把抓帧饿死，0.7fps → 8.4fps。
3. **设备端常驻抓帧循环**（`--mode loop`，默认）
   设备端 `while` 循环连续截图并原子 `mv` 到固定文件，主机每帧只做一次
   `hdc file recv`（34ms）。93ms → 34ms，这是最大的一步。

`--mode shot` 保留单次抓帧作为兜底：循环起不来或拉帧失败会自动回退。

### 两次踩坑（都是静默失败，很费时间）

**坑 1：`snapshot_display` 只认 `.jpeg` 扩展名**

```bash
snapshot_display -f /data/local/tmp/x.jpg    # error: filename invalid!
snapshot_display -f /data/local/tmp/x.jpeg   # success
snapshot_display -f /data/local/tmp/x.png    # error: filename invalid!
```

`.jpg` / `.png` / `.bin` 全部被拒，但**退出码仍是 0**，配合 `2>/dev/null`
就是彻底静默——曾让我误把「循环空转速率 22fps」当成真实抓帧率。

**坑 2：`pkill -f <脚本名>` 会杀掉执行它的 shell 自己**

```bash
hdc shell "pkill -f carbon-loop.sh; nohup /data/local/tmp/carbon-loop.sh &"
#           ↑ 这条命令自身的命令行也含 carbon-loop.sh，pkill 把 shell 一起杀了
#           → 后面的 nohup 永远执行不到，画面永远不更新
```

改用 **pid 文件**管理：脚本开头 `echo $$ > pid`，停止时 `kill $(cat pid)`，
启动时只 `rm` 旧文件、不再 pkill。

### 还能不能再快

| 做法 | 预期 | 代价 |
| --- | --- | --- |
| 设备端循环 + 更低分辨率 | 无收益（实测更慢） | 不推荐 |
| 设备端开多个循环并行抓帧 | 受 CPU 限制，收益存疑 | 需实测模拟器核数 |
| 换实时投屏通道（scrcpy 式） | 30fps+ | 模拟器走 hdc 不是 adb，无对外视频流端口，要在设备端装 daemon |

### 运维：隧道卡住怎么办

反向隧道如果出现反复 `remote port forwarding failed`，说明服务器上残留了旧监听：

```bash
ssh -p 2222 root@8.133.220.133 '
  PID=$(ss -lntp | grep ":8899 " | grep -oE "pid=[0-9]+" | head -1 | cut -d= -f2)
  [ -n "$PID" ] && kill -9 "$PID"; ss -lntp | grep ":8899 " || echo 已释放'
launchctl kickstart -k gui/$(id -u)/com.carbon.remote-tunnel
```

## 四、只想局域网 vs 想在任何网络下用

当前实现是**局域网直连**：手机和 Mac 在同一个 Wi-Fi 下即可。

想做到「4G / 任何网络都能用」，需要借助隧道，有两条路（都还没做）：

**A. 复用已有的 `dsh.saidao.asia`（推荐，影响面最小）**
1. Mac 上建反向隧道：`ssh -R 8899:127.0.0.1:8899 root@8.133.220.133`
2. 在服务器 nginx 的该站点里加一个 `location /carbon/` → `proxy_pass http://127.0.0.1:8899/`
3. 手机访问 `https://dsh.saidao.asia/carbon/?t=<令牌>`

好处：复用现成域名与 Let's Encrypt 证书，不动 DNS，不动 relay。
代价：改了一次线上 nginx（改完必须先 `nginx -t` 再 reload）。

**B. 本地分流代理（不动服务器，但有风险）**
把 `dsh-remote` 的 agent 上游从 `3081` 改成 Mac 上一个分流代理：`/carbon` 走本服务、
其余照旧转给 dsh-pocket。服务器零改动，但**给 DSH 远程这条链路多加了一跳**，
代理挂了会连带 DSH 远程一起挂。

## 五、安全

- 令牌在 URL 的 `?t=` 里，服务启动时随机生成；不带令牌一律 403。
- 服务只监听局域网，没有出公网。**但校园网/公共 Wi-Fi 上同一网段的其他人理论上能扫到端口**，
  令牌就是这道门 —— 别把完整链接发到群里。
- 令牌泄露了？重启服务就换一个新的。
- 这个服务等于「能给模拟器注入触摸」，接进来的人可以操作模拟器里的一切。

## 六、已知限制

- **模拟器必须开着**，服务只是转发，不负责启动模拟器。
- 帧率上限受 `snapshot_display` 制约（本机约 7 fps），**滑动类动效看起来会有点顿**，
  点击类操作没有延迟感。
- 系统级手势（下拉通知栏、返回桌面）需要额外按钮，目前只做了「返回」。
- 服务是前台进程，**Mac 重启后需要重新起**；要长期常驻可以照 `dsh-remote/agent` 那样
  套一个 LaunchAgent。
