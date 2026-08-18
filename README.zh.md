# NeonNotify（霓虹通知）

[English](README.md) · **中文**

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

## 安装

不依赖 Xcode，SwiftPM + 脚本就能打包，有 Command Line Tools 即可：

```bash
./Scripts/make_app.sh
cp -R build/NeonNotify.app /Applications/
open /Applications/NeonNotify.app
```

装到 `/Applications` 再接 hooks —— hooks 里写的是绝对路径，app 换位置就得重装。

## 接上 Claude Code

设置面板 → **Claude Code** → **安装 hooks**。或者用命令行：

```bash
/Applications/NeonNotify.app/Contents/MacOS/neon-hook --install     # 安装（自动备份原配置）
/Applications/NeonNotify.app/Contents/MacOS/neon-hook --status      # 查看状态
/Applications/NeonNotify.app/Contents/MacOS/neon-hook --uninstall   # 卸载
```

安装会把 hooks 合并进 `~/.claude/settings.json`，只增加自己的条目，其余配置
（`model` / `env` / 你自己的 hooks）原样保留，改动前备份成
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

- **通用**：开机启动、显示器选择、窗口层级（所有窗口顶部或底部）
- **灯效**：13 套配色预设、灯带宽度、屏幕圆角、光晕、速度、流动样式（跑马灯 / Claude Code 流水，见下）、强度、方向
- **Claude Code**：装卸 hooks、撒花、系统通知、红/绿提示音、绿灯保持时长、黄灯超时

面板底部有实时会话列表和四个预览按钮，不用真跑一轮 Claude 也能看灯效。

### 流动样式：Claude Code 流水

除了默认的跑马灯（一段白色亮弧绕圈跑），灯带还能跑 Claude Code 干活时终端顶部那条流水灯：
一个压到全黑的缺口沿着灯带匀速绕圈，约 1140pt/秒。缺口只按 alpha 把灯带挖暗，不叠白光，
所以你自己的颜色 —— 空闲时的彩虹、或者黄红绿交通灯 —— 全都原样保留。

缺口沿边框的真实弧长走（`trim`），四条边和四个角速度、宽度都一致。形状上比终端里那条线硬一些：
原版两侧各接约 680pt 的线性斜坡，这里是 520pt 实心黑加 60pt 柔化边 —— 真按原版那么柔，
缺口要占掉近三成周长，暗的部分太多反而不好看。

## 项目结构

```
Sources/
  NeonCore/      app 与 hook 共用：状态模型、事件映射、状态文件读写、hooks 安装器
  NeonNotify/    菜单栏 app：灯带窗口与渲染、状态聚合、通知、设置面板
  neon-hook/     被 Claude Code 调用的 CLI
  strip-probe/   调试工具：并排渲染多种灯带 / 撒花变体
Scripts/make_app.sh   Scripts/make_icon.swift
```

改代码之前建议先看 [实现笔记](docs/notes.md) —— hook 事件时序、Ctrl+C 中断检测、
Metal 视图在透明窗口里的渲染坑，都是花过时间才定位到的。

## 致谢

- [ColorfulX](https://github.com/Lakr233/ColorfulX) —— Metal 动画渐变，灯带的底色
- [ConfettiSwiftUI](https://github.com/simibac/ConfettiSwiftUI) —— 完成时的撒花
- [SettingsAccess](https://github.com/orchetect/SettingsAccess) —— 从 MenuBarExtra 打开设置面板
- 屏幕跑马灯 / Strip Light（`com.yukihakarigoto.StripLight`）—— 灯带形态的灵感来源
