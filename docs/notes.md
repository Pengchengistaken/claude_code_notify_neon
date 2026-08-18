# 实现笔记

从 README 里挪出来的踩坑记录。改这个项目之前值得先看一遍，都是花过时间才定位到的问题。

## hook 事件时序的坑

回合结束后并不是就没事件了，这些迟到事件都会污染灯色，必须挡掉：

- **`SubagentStop` 比 `Stop` 晚约 4 秒到**。当成「运行中」的话，刚亮起的绿灯会被打回黄灯，
  然后一直挂到超时。现在直接忽略这个事件 —— 子代理期间的状态本来就由 Task 工具的
  `PreToolUse`/`PostToolUse` 覆盖。
- **Claude Code 闲置约 60 秒会发一条「在等你输入」的 `Notification`**。全部当成
  「等待确认」的话，已经回到彩虹的灯带会无端变红并响铃。

统一的规则是：只要会话的上一个事件是 `Stop`（回合已结束），就只认
`UserPromptSubmit` / `SessionStart` / `SessionEnd` / `PermissionRequest`，
其余一律不写。权限询问只可能发生在回合进行中，所以这样不会漏掉红灯。

## Ctrl+C 取消：没有事件，只能读对话记录

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

## 渲染上的两个坑

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

**`.mask()` 里的动画不会跑。** 「流水」的缺口一开始是当遮罩用的：SwiftUI 照常渲染了遮罩的
内容（缺口该暗的地方确实暗了），但不驱动它里面的 `repeatForever`，缺口定在原地不动 ——
逐帧截图做互相关，实测转速正好是 0。改成把缺口留在正常视图树里、用 `.destinationOut`
按 alpha 挖暗就正常了。用 `destinationOut` 同样得先 `.compositingGroup()` 把要挖的两层
圈起来，否则会一路挖穿到透明的窗口底。

撒花那边：`.confettiCannon` 挂在 `.overlay(alignment: .top)` 里的 1x1 锚点上时，
一颗粒子都不会画出来；要直接挂在撑满的容器上。

## 调试工具

`swift run strip-probe` 会铺一层透明覆盖窗，同屏画出若干渲染变体后 20 秒自动退出，
配合截图用来定位「灯带颜色不对」这类问题。

## 开机启动为什么用 SMAppService

用的是系统的 `SMAppService`（macOS 13+），没有采用 LaunchAtLogin-Legacy：
后者需要内嵌 helper app 和 Xcode 的 Copy Files 构建阶段，SwiftPM 脚本打包做不到。
