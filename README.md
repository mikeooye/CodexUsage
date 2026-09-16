# Codex Usage

极简 macOS 菜单栏 App：显示 Codex 5 小时 / 7 天额度的**剩余百分比**和重置时间。

## 要求
- macOS 13+
- Xcode / Command Line Tools
- 已安装并登录 Codex CLI，终端执行 `codex --version` 可用

## Xcode 打开
直接用 Xcode 打开 `Package.swift`，选择 `CodexUsage` scheme 后 Run。

## 生成 .app
```bash
./scripts/build-app.sh
open '.build/Codex Usage.app'
```

## 数据与隐私
App 不读取 `~/.codex/auth.json`。它启动本机 `codex app-server`，通过 JSON-RPC 调用 `account/read` 与 `account/rateLimits/read`。默认每 120 秒刷新一次。

## 当前界面
菜单栏：`5 小时 82% · 7 天 47%`

点击后显示两个进度条、各自重置时间、刷新按钮和最后更新时间。
