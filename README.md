# VibePulse

> 为 Vibe Coding 打造的原生 macOS 菜单栏仪表盘。

![Platform](https://img.shields.io/badge/macOS-15%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/License-MIT-green)

VibePulse 将 Claude Code、Codex 的连接状态、订阅额度、本机 Token 用量与 Mac 系统状态集中在一个紧凑的菜单栏面板中。无需反复打开多个应用，即可掌握 AI 编程额度、保持 Mac 持续运行，并快速查看当前设备状态。

## 功能亮点

- **AI 编程额度**：展示 Claude Code 与 Codex 的 5 小时、7 天剩余额度和重置时间
- **连接状态**：独立检测 Claude Code 与 Codex 官方客户端登录状态
- **用量概览**：汇总本机今日、本周、本月 Token，并显示 API 等价美元估值
- **保持唤醒**：支持永久、1 小时、2 小时、4 小时防睡计时
- **合盖运行**：可选系统级合盖不休眠模式
- **系统监控**：查看 CPU、内存、电池、开机时长、公网 IP 与国家
- **原生体验**：SwiftUI 构建，支持深色、浅色与跟随系统模式
- **Liquid Glass**：macOS 26 使用原生液态玻璃效果

## 数据来源

| 数据 | 来源 |
| --- | --- |
| Claude 5 小时 / 7 天额度 | Anthropic 官方 OAuth 用量接口 |
| Codex 5 小时 / 7 天额度 | Codex 官方本地 `app-server` |
| Claude / Codex Token | 本机保存的官方客户端会话日志 |
| 美元估值 | 按日志模型和分类 Token，以公开 API 单价估算 |
| 系统状态 | macOS 本地系统接口 |
| 公网 IP 与国家 | `ipwho.is` |

> `≈$` 金额表示等价 API 价值，并非 Claude Pro、Codex Plus 等订阅的实际扣费。

VibePulse 每 5 分钟自动调用 Claude 与 Codex 官方接口刷新连接状态、5 小时额度和 7 天额度；Mac 从睡眠唤醒后也会立即刷新。即使未打开 Claude Code 或 Codex，额度仍会保持更新。

## 安全与隐私

- 所有 Token 用量统计均在本机完成
- 不保存、不展示 Claude 或 Codex 登录令牌
- Claude OAuth 凭据仅从 macOS 钥匙串临时读取，并仅发送至 Anthropic 官方接口
- Codex 额度通过官方本地服务读取
- 合盖不休眠首次使用需要管理员授权，之后由权限受限的本地助手切换

## 系统要求

- macOS 15 或更高版本
- Xcode 26 或兼容 Swift 6 工具链
- Claude Code / Claude Desktop，可选
- Codex Desktop / Codex CLI，可选

## 构建运行

```bash
git clone https://github.com/ecokater/VibePulse.git
cd VibePulse
chmod +x build-app.sh
./build-app.sh
open dist/VibePulse.app
```

构建 DMG 安装包：

```bash
chmod +x build-dmg.sh
./build-dmg.sh
```

构建产物位于：

```text
dist/VibePulse.app
```

## Claude Code 登录

Claude Desktop 与 Claude Code 使用独立登录状态。VibePulse 会自动识别独立安装或 Claude Desktop 内置的 Claude Code。

```bash
claude auth login
```

如果终端中的 Claude Code 未继承系统代理，可为登录命令设置 `HTTPS_PROXY`、`HTTP_PROXY` 和 `ALL_PROXY`。

## 注意事项

- 合盖不休眠会禁用系统睡眠。请保持设备通风，避免放入电脑包中持续运行
- 本机 Token 统计依赖官方客户端保留的会话日志
- 模型价格可能变化，美元估值仅供参考
- Claude Code、Claude、Codex、Anthropic 与 OpenAI 商标归各自所有

## 技术栈

- SwiftUI
- ServiceManagement
- macOS `pmset` / `caffeinate`
- Swift Package Manager

## License

[MIT](LICENSE) © 2026 ecokater
