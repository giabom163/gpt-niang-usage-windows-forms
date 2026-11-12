# Windows 开发说明

安装、设置和来源见[项目 README](../README.md)。

| 模块 | 作用 |
| --- | --- |
| `widget.ps1`、`widget.xaml`、`runtime/ui-settings.ps1` | WPF 挂件、外观设置、气泡与交互 |
| `runtime/effort-form.ps1`、`runtime/native-effort.cs` | 五档映射、原生强度控件读取、会话后备和立绘选择 |
| `Install.ps1`、`Uninstall.ps1`、`runtime/supervisor*.ps1` | Windows 安装、停用及随 Codex 窗口启动 |
| `runtime/usage.mjs`、`runtime/plan.mjs`、`runtime/mcp.mjs` 等 | 额度、套餐、MCP 和刷新基础 |
| `assets`、`tests` | 语录、素材来源说明及回归测试 |

从本目录运行 `npm test` 可检查 Node 模块。使用[仓库自带素材](assets/forms/README.txt)，运行 `npm run test:windows` 可检查 Windows 安装与 WPF 入口。Windows 版本保留了被 Node 测试引用的共享模块，本源码树的发布与验收目标是 Windows。

开发时可通过挂件外观菜单切回纯 Q、固定档位或恢复随强度变化。改动原生控件识别后，请在空白页连续切多档，再打开模型菜单，核对立绘与滑杆最后选定的档位。
