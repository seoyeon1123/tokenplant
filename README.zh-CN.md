# TokenPlant

[English](README.md) · [한국어](README.ko.md)

一个 macOS 菜单栏应用：使用 AI 编程工具消耗 Token，像素植物就会生长。长成后移栽到花园，花盆里重新种下一颗种子。

## 语言

源码构建版本支持韩文和简体中文，跟随 macOS 的语言偏好。不支持的语言回退到韩文。也可以在“系统设置 → 通用 → 语言与地区 → 应用程序”中为 TokenPlant 选择语言，随后重新启动应用。

语言只影响显示文案，存档中的植物 ID、道具 ID、余额和用量统计不随语言变化。官方发行版是否已经包含中文支持，以发布的版本为准。

## 安装与构建

需要 macOS 14 或更高版本，以及 Claude Code 或 Codex 的本地会话日志。源码构建需要 Xcode 或 Command Line Tools：

```sh
git clone https://github.com/seoyeon1123/tokenplant.git
cd tokenplant
./build-app.sh --install
```

构建脚本生成 Apple Silicon 和 Intel 通用应用；如果通用构建失败，会尝试只构建当前机器架构。应用保留原有自动更新机制。

其他安装方式、未公证应用的打开方法和版本发布信息，见 [English README](README.md#install)。

## 用量与存档

- Claude Code：`~/.claude/projects/**/*.jsonl`
- Codex：`~/.codex/sessions/YYYY/MM/DD/*.jsonl`
- 存档：`~/Library/Application Support/TokenPlant/state.json`

应用每 30 秒读取本地用量，Token 同时用于植物生长和钱包积累。商店购买道具不会扣除已有的生长进度。没有这些日志的网页或桌面聊天用量无法统计。

钱包余额不会在午夜清零。使用前的历史日志用于估算日均用量，不直接追补成生长奖励。连续使用可获得额外奖励；水、肥料和营养剂能加快生长。

可选的“用量限额奖励”会读取 Claude Code 已保存的凭据以查询自己的限额；默认关闭。拒绝钥匙串访问不影响基本生长。

## 参与翻译

简体中文模板位于 `Sources/TokenPlant/Core/ChineseTranslations.swift`。韩文原文作为查找键；`{0}`、`{1}` 等表示对应的插值内容，翻译时可调整顺序，但不能删除或增加占位符。运行 `swift test` 检查语言回退、插值、与显示语言无关的商店分类和模板占位符。

新增或修改装饰名称时，继续维护 `verify/gen_decor.py` 中的原始数据；展示名称在 `DecorIcons.name` 中翻译。

项目采用 [MIT License](LICENSE)。
