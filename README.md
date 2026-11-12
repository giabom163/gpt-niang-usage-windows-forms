# GPT 娘额度挂件 · Windows 五档立绘版

基于 [T7moris / GPT-Niang v1.3.1](https://github.com/T7moris/GPT-Niang/tree/v1.3.1) 二次开发。保留额度气泡、语录与点击交互，支持从轻度到 Ultra 的五档立绘、纯 Q、固定形象、角色宽高和独立气泡缩放。打开空白新对话拖动 Codex 原生推理强度滑杆即可换图。

## Windows 一键安装

需要已安装的 Codex 桌面客户端和可从 PATH 找到的 Node.js 20 或更新版本。打开 PowerShell，粘贴整行并回车：

```powershell
$p = Join-Path ([IO.Path]::GetTempPath()) ('GPTNiangForms-' + [guid]::NewGuid().ToString('N') + '.ps1'); Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/giabom163/gpt-niang-usage-windows-forms/v1.0.0/Install-Windows.ps1' -OutFile $p; powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $p
```

脚本从 GitHub 拉取固定版本的完整源码和素材，解压到 `%LOCALAPPDATA%\Programs\GPTNiangForms`，随后注册 Codex 本地插件、登录计划任务和启动快捷方式。公开版自带新绘的简版五档角色和合成音效。视频演示立绘为另一套素材。

已经安装上游或其他目录的 GPT 娘时，先在旧目录运行停用入口，再装此版。设备脚本策略由系统或组织管理时，遵守该策略。

### 给 Codex 的安装口令

> 在我的 Windows 上安装 https://github.com/giabom163/gpt-niang-usage-windows-forms 的 v1.0.0。打开 README，执行 Windows 一键安装命令。先检查 Node.js 20+ 和 Codex 桌面端是否齐全，安装完成后告诉我安装位置和结果。遇到旧版冲突先告诉我。

### 只下载或本地安装

- 在一键命令的结尾加 `-DownloadOnly`，只拉取仓库到本地。
- 也可以下载 [v1.0.0 源码 ZIP](https://github.com/giabom163/gpt-niang-usage-windows-forms/archive/refs/tags/v1.0.0.zip)，解压后在项目根目录执行 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Install-Windows.ps1`。
- 已解压时，给上述本地命令加 `-CheckOnly` 可检查安装环境和已有注册。测试和模块结构见 [Windows 开发说明](gpt-niang-usage/README.md)。

## 来源

- 原插件：[T7moris / GPT-Niang](https://github.com/T7moris/GPT-Niang)，二次开发基线为 `76859a8ba993103f9561b8388dd7c8dc94996446`。
- 五档进化灵感：[白龙娘的进化历程 BV1ghx76KERV](https://www.bilibili.com/video/BV1ghx76KERV/)。
- 交互参考：[MeteorNOX / DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)。语录引用见 [语录许可](gpt-niang-usage/assets/quotes-LICENSE.txt)。
- 源码附 [MIT 许可](LICENSE)。公开版附带的自制素材允许随此项目分发，替换路径见[素材清单](gpt-niang-usage/assets/forms/README.txt)。
