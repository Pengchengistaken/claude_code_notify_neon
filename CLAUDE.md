# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NeonNotify：macOS 菜单栏应用，在屏幕四边画一圈霓虹灯带，并把它当成 Claude Code 的交通灯
（🟡 运行中 / 🔴 等待确认 / 🟢 完成 / ⚪️ 空闲）。

## 常用命令

```bash
swift build                      # 快速编译检查（debug）
./Scripts/make_app.sh            # 完整打包：swift build -c release + 组装 .app + ad-hoc 签名
swift run strip-probe            # 调试工具：同屏并排画若干渲染变体，20 秒后自动退出

# 改完代码后完整验证一遍（app 必须从 /Applications 运行，hook 里写的是绝对路径）
osascript -e 'quit app "NeonNotify"' ; ./Scripts/make_app.sh \
  && rm -rf /Applications/NeonNotify.app && cp -R build/NeonNotify.app /Applications/ \
  && open /Applications/NeonNotify.app
```

没有测试目标，也没有 lint 配置；验证靠跑起来看 + 截图（`screencapture -x out.png`）。

调试开关：

```bash
# 状态聚合逐次打印到 stderr（读到什么 / 判定成什么 / 文件多旧）
NEONNOTIFY_DEBUG=1 /Applications/NeonNotify.app/Contents/MacOS/NeonNotify 2>&1 | grep 聚合=

# 抓 hook 事件原文：建这个标记文件后，每个事件都会追加到 events.log
touch ~/.claude/neon-status/.debug && tail -f ~/.claude/neon-status/events.log

# hook 装卸（等价于设置面板里的按钮）
/Applications/NeonNotify.app/Contents/MacOS/neon-hook --install | --uninstall | --status
```

**改了 hook 相关逻辑后，必须重开一个 Claude Code 会话才生效**（hooks 只在会话启动时读取）。

## 架构

进程间只通过文件 + Darwin 广播通信，没有轮询、没有常驻连接：

```
Claude Code ──(事件 JSON 走 stdin)──> neon-hook
                                        │ 原子写 + CFNotificationCenter 广播
                                        ▼
                        ~/.claude/neon-status/<session_id>.json
                                        │ kqueue 目录监听 + Darwin 通知（双通道兜底）
                                        ▼
                                   NeonNotify.app
```

四个 target（见 `Package.swift`）：

- **NeonCore** —— app 与 hook 共享的数据契约。`TrafficState`（rawValue 会落盘，**改它等于改协议**）、
  `SessionStatus`、`StatusPaths`（目录/原子写/陈旧清理）、`HookEventMapping`（事件→状态）、
  `HookInstaller`（合并进 `~/.claude/settings.json`）、`TranscriptInspector`（读对话记录查 Ctrl+C）。
- **neon-hook** —— Claude Code 调用的 CLI。铁律写在 `main.swift` 顶部：**永远 exit(0)、绝不写 stdout、要快**。
  兼作 `--install/--uninstall/--status` 子命令。
- **NeonNotify** —— 菜单栏 app。`AppCoordinator` 是中枢（偏好 / 状态 / 窗口 / 通知 / 撒花）。
- **strip-probe** —— 渲染调试工具，不进 app bundle。

app 内部：`StatusWatcher`（监听目录）→ `StatusStore`（聚合成 `effectiveState`）
→ `StripWindowManager`（每块屏幕一个 `OverlayWindow`）→ `StripView`（渲染）；
状态变化同时触发 `Notifier`（通知+提示音）和 `ConfettiPresenter`（撒花）。

### 状态判定的三条规则

灯色不是 hook 写什么就显示什么，`StatusStore.resolvedState` 会重新推导：

1. **落盘的是事件名，app 侧按当前设置重新映射**（`HookEventMapping.state`），所以改设置不用重装 hook。
2. **绿灯保持 `greenHoldSeconds` 秒后衰减回 idle；黄/红灯超过 `staleMinutes` 视为陈旧忽略**
   （进程被 kill 时收不到 `Stop`）。文件系统不会再来事件，靠 `decayTimer` 主动重算。
3. **Ctrl+C 中断只能从对话记录里读**（Claude Code 没有取消事件）。灯亮着时每 2 秒读一次
   transcript 尾部 64KB，中断时间晚于最后一个 hook 事件就判定为 idle。空闲时定时器停掉。

多会话聚合优先级：红 > 黄 > 绿 > idle。

### 回合结束后的迟到事件必须挡掉

`Stop` 之后还会陆续来事件，直接采信会污染灯色。规则在 `HookEventMapping`：
`SubagentStop` 完全忽略（比 `Stop` 晚约 4 秒到，会把绿灯打回黄灯）；上一个事件是 `Stop` 时，
只认 `UserPromptSubmit` / `SessionStart` / `SessionEnd` / `PermissionRequest`
（`shouldOverrideFinishedTurn`），否则闲置 60 秒的那条"在等你输入"`Notification` 会让灯莫名变红。
未知事件一律只记日志、不改状态。

### 渲染层的硬性约束

改 `Lighting/` 下的代码前先读 `docs/notes.md`，那里记的每一条都花过时间定位。最要命的几条：

- **长期跑的动画必须拆成只吃值类型入参的独立 `View`**（`StreamNotch`、`RainbowRing`），
  自己在 `onAppear` 里点火。留在 `StripView` 里会被 `StatusStore` 每 2 秒的轮询重绘打断，
  `repeatForever` 再也接不上，画面定格 —— 而定格的样子常常看着像"另一个 bug"。
- **`.mask()` / `.blendMode` 层里的 `rotationEffect` 动画不会被驱动**，只有 `.trim` 能动。
  流水缺口因此用 `trim`（还顺带保证沿边框匀速，角向渐变在拐角会宽约 20%）。
- **用 `.compositingGroup()`，绝不用 `.drawingGroup()`** —— 后者会把 ColorfulX 的 Metal 内容
  离屏重光栅化，整条彩虹被压成一片亮黄。但混合模式又必须有合成边界，否则会和透明窗口背景相混、整条消失。
- `repeatForever` 只在绑定值变化时启动，所以点火写法一律是"先归零，再 `DispatchQueue.main.async` 置起"。
- 判断动画到底动没动，别靠肉眼看截图：逐帧沿边框采一圈亮度，排成「横轴=绕圈位置、纵轴=时间」的热力图。

## 约定

- **代码注释、文档、commit message 全部用中文**，注释写"为什么这么做"而不是"这行做了什么"。
- 界面文案是中文；`README.md` 英文、`README.zh.md` 中文，两边要同步改。
- 排查过程中的坑，结论沉淀到 `docs/notes.md`，不要堆在 README 里。
- 这台机器只有 Command Line Tools，没有 Xcode —— `.app` 由 `Scripts/make_app.sh` 手工拼，
  任何需要 Xcode 构建阶段的方案（比如内嵌 helper app 做开机启动）都用不了，开机启动走 `SMAppService`。
- 图标由 `swift Scripts/make_icon.swift <输出目录>` 生成，产物 `Resources/AppIcon.icns` 已入库，只在要改图标时手工跑。
