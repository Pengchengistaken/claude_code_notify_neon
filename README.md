# NeonNotify（霓虹通知）

环绕屏幕的霓虹跑马灯，同时也是 Claude Code 的交通灯。

> **不用自己动手装。** 这份 README 是写给 AI 看的 —— 把下面这个地址丢给你的 AI
> （Claude Code、Cursor、Codex 都行），让它帮你编译出 app 就行：
>
> ```
> https://github.com/Pengchengistaken/claude_code_notify_neon
> ```
>
> 后面的构建、安装、接 hooks 的步骤它自己会看懂，你只要在它问你要权限的时候点同意。

平时它就是一条不停流动的彩色灯带；开启 Claude Code 通知后，整条灯带变成状态指示：

| 灯色 | 含义 | 触发时机 |
|---|---|---|
| 🟡 黄 | 正在运行 | 提交提问、工具调用前后、子代理运行 |
| 🔴 红 | 等待确认 | 权限询问、Claude 在等你回话 |
| 🟢 绿 | 运行完成 | 本轮回答结束（撒花 + 提示音 + 系统通知） |
| ⚪️ 灭 | 空闲 | 无活动，回到默认彩虹配色 |

<table>
<tr>
<td width="50%"><img src="docs/screenshots/idle.png" alt="空闲：灯带走彩虹配色"></td>
<td width="50%"><img src="docs/screenshots/running.png" alt="正在运行：整条灯带转成黄色"></td>
</tr>
<tr>
<td><b>⚪️ 空闲</b> —— 没有会话在跑，灯带走默认彩虹配色</td>
<td><b>🟡 正在运行</b> —— 提交提问、工具调用前后都是黄灯</td>
</tr>
<tr>
<td><img src="docs/screenshots/waiting.png" alt="等待确认：灯带转红并弹出通知"></td>
<td><img src="docs/screenshots/finished.png" alt="运行完成：灯带转绿并撒花"></td>
</tr>
<tr>
<td><b>🔴 等待确认</b> —— 权限询问，红灯 + 提示音 + 通知横幅</td>
<td><b>🟢 运行完成</b> —— 绿灯 + 撒花 + 提示音 + 通知横幅</td>
</tr>
</table>

通知走 `UNUserNotificationCenter`，横幅上显示的是 NeonNotify 自己的名字和图标，
不会像默认的 `osascript` 方案那样冒充 "Script Editor"。

## 构建

> 这一节往下都是给 AI 看的操作手册。自己不想折腾就把仓库地址交给 AI，让它照着做。

不依赖 Xcode，SwiftPM + 脚本就能打包 —— 有 Command Line Tools 即可，`.app` 由脚本手工组装：

```bash
./Scripts/make_app.sh
open build/NeonNotify.app
```

建议装到 `/Applications` 再安装 hooks —— hooks 里写的是绝对路径，app 换位置就得重装：

```bash
cp -R build/NeonNotify.app /Applications/
open /Applications/NeonNotify.app
```

## 接上 Claude Code

设置面板 → **Claude Code** → **安装 hooks**。或者用命令行：

```bash
/Applications/NeonNotify.app/Contents/MacOS/neon-hook --install     # 安装（自动备份原配置）
/Applications/NeonNotify.app/Contents/MacOS/neon-hook --status      # 查看状态
/Applications/NeonNotify.app/Contents/MacOS/neon-hook --uninstall   # 卸载
```

安装会把 hooks 合并进 `~/.claude/settings.json`，只增加自己的条目，
其余配置（`model` / `env` / 你自己的 hooks）原样保留，改动前备份成
`settings.json.neonbak-<时间戳>`（只保留最近 5 份）。

**hooks 需要重开 Claude Code 会话才生效。**

## 工作原理

```
Claude Code
   │  hook 事件 (stdin JSON)
   ▼
neon-hook           无依赖 CLI，单次约 7ms，永远 exit 0，不向 stdout 输出
   │  原子写 + Darwin notification
   ▼
~/.claude/neon-status/<session_id>.json
   │  kqueue 目录监听 + Darwin notification 双通道
   ▼
NeonNotify.app      多会话聚合（红 > 黄 > 绿 > 空闲）→ 灯带 / 通知 / 撒花
```

- **不轮询**：靠文件系统事件和 Darwin 广播推送，空闲时零开销。
- **app 没开也不影响 Claude Code**：hook 只是写个文件，任何异常都静默 exit 0。
- **多窗口**：每个会话一个状态文件，取优先级最高的显示；进程被 kill 时靠超时和陈旧清理兜底。

## 设置项

- **通用**：开机启动、显示器选择（全部 / 仅主屏 / 除主屏外）、窗口层级（所有窗口顶部或底部）
- **灯效**：默认配色（13 套 ColorfulX 预设）、灯带宽度、屏幕圆角、光晕、速度、跑马灯强度、方向
- **Claude Code**：装卸 hooks、撒花、系统通知、红/绿提示音、绿灯保持时长、黄灯超时、
  是否把 `PreToolUse` 也当成等待确认（默认关 —— 当前 Claude Code 有精确的权限询问事件，用它判断更准）
- 面板底部有实时会话列表和四个预览按钮，不用真跑一轮 Claude 也能看灯效

## 项目结构

```
Sources/
  NeonCore/      app 与 hook 共用：状态模型、事件映射、状态文件读写、hooks 安装器
  NeonNotify/    菜单栏 app：灯带窗口与渲染、状态聚合、通知、设置面板
  neon-hook/     被 Claude Code 调用的 CLI
  strip-probe/   调试工具：在同样的透明全屏窗口里并排渲染多种变体（灯带管线 / 撒花布局）
Scripts/make_app.sh   Scripts/make_icon.swift
```

`swift run strip-probe` 会铺一层透明覆盖窗，同屏画出若干渲染变体后 20 秒自动退出，
配合截图用来定位「灯带颜色不对」这类问题。

### hook 事件时序的坑

回合结束后并不是就没事件了，这些迟到事件都会污染灯色，必须挡掉：

- **`SubagentStop` 比 `Stop` 晚约 4 秒到**。当成「运行中」的话，刚亮起的绿灯会被打回黄灯，
  然后一直挂到超时。现在直接忽略这个事件 —— 子代理期间的状态本来就由 Task 工具的
  `PreToolUse`/`PostToolUse` 覆盖。
- **Claude Code 闲置约 60 秒会发一条「在等你输入」的 `Notification`**。全部当成
  「等待确认」的话，已经回到彩虹的灯带会无端变红并响铃。

统一的规则是：只要会话的上一个事件是 `Stop`（回合已结束），就只认
`UserPromptSubmit` / `SessionStart` / `SessionEnd` / `PermissionRequest`，
其余一律不写。权限询问只可能发生在回合进行中，所以这样不会漏掉红灯。

### Ctrl+C 取消：没有事件，只能读对话记录

**Claude Code 没有任何取消/中断的 hook 事件**（实测按 Ctrl+C 后既不发 `Stop`
也不发 `PermissionDenied`，`MessageDisplay` 只是助手文本的流式分片，不带中断标识）。
最后一个事件停在 `PreToolUse`/`PostToolUse` 上，灯带就会一直黄到超时。

好在中断一定会写进对话记录：一条 `type: "user"` 且带顶层 `interruptedMessageId`
字段的记录，时间戳就是按下 Ctrl+C 的时刻。记录路径每个 hook payload 都带
（`transcript_path`），hook 把它一并存进状态文件，app 在灯亮着的时候每 2 秒
读一次记录尾部（只读最后 64KB）；只要中断时间晚于最后一个 hook 事件，
就判定这一轮已被掐断，灯带回到空闲。空闲时定时器会停掉，不产生开销。

排查这类问题把 app 用 `NEONNOTIFY_DEBUG=1` 跑起来，每次状态重算都会把
「读到了什么、判定成什么」打到 stderr：

```
NEONNOTIFY_DEBUG=1 /Applications/NeonNotify.app/Contents/MacOS/NeonNotify 2>&1 | grep 聚合=
聚合=finished 会话数=1 bdb3bd2f[Stop 落盘=finished 判定=finished age=0.4s]
聚合=idle     会话数=1 bdb3bd2f[Stop 落盘=finished 判定=idle     age=6.2s]
```

### 渲染上的两个坑

灯带把 ColorfulX 的 Metal 视图放在透明穿透窗口里，这个组合有两个反直觉的地方：

- **不能用 `.drawingGroup()`**。它会把 Metal 内容离屏重新光栅化，颜色会坏掉 ——
  整条彩虹被压成一片均匀的亮黄色。要用 `.compositingGroup()`。
- **但混合模式必须有合成边界**。跑马高光用了 `.plusLighter`，若外面没有
  `.compositingGroup()`，它会直接和透明的窗口背景相混，整条灯带会彻底消失。

动画也不要用 `TimelineView` 每帧重建视图树：全屏尺寸下那样常驻 12% CPU，
改成 CoreAnimation 的 `repeatForever` 后降到 ~9%。

用 CoreAnimation 就要注意 `repeatForever` 只在绑定值变化时启动：状态切换会换掉底色视图，
持续动画不会自己接上，必须在 `onChange(of: appearance)` 里重新点火，否则灯带切回彩虹后
颜色会定格不转。

「彩虹」配色走的是角向渐变而不是 ColorfulX：色块式渐变某些时刻整圈会被暖色占满，
跟「运行中」的黄灯撞色。角向渐变还得撑到对角线大小的正方形再 `rotationEffect`，
否则非正方形屏幕转起来四角会露空。

撒花那边：`.confettiCannon` 挂在 `.overlay(alignment: .top)` 里的 1x1 锚点上时，
一颗粒子都不会画出来；要直接挂在撑满的容器上。

## 致谢

- [ColorfulX](https://github.com/Lakr233/ColorfulX) —— Metal 动画渐变，灯带的底色
- [ConfettiSwiftUI](https://github.com/simibac/ConfettiSwiftUI) —— 完成时的撒花
- [SettingsAccess](https://github.com/orchetect/SettingsAccess) —— 从 MenuBarExtra 打开设置面板
- 屏幕跑马灯 / Strip Light（`com.yukihakarigoto.StripLight`）—— 灯带形态的灵感来源

开机启动用的是系统的 `SMAppService`（macOS 13+），没有采用 LaunchAtLogin-Legacy：
后者需要内嵌 helper app 和 Xcode 的 Copy Files 构建阶段，SwiftPM 脚本打包做不到。
