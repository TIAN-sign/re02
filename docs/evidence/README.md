# 实际运行证据

这些 PNG 由 **Godot 4.6.3** 实际渲染生成，环境为 Linux、临时 Xorg 显示与 Mesa llvmpipe Compatibility 渲染器。截图脚本通过真实 InputMap 注入键盘事件，在实际物理 tick 调用生产输入、训练、战斗与场景代码；没有替换战斗模块或直接伪造生命值、胜负、角色位置。

| 画面 | 可观察结果 |
| --- | --- |
| [对战初始状态](versus.png) | 两名角色、完整 HUD、双方满血 |
| [训练判定框](training-hitboxes.png) | 第 88 帧，轻击有效阶段，P2 生命 920，输入历史及真实判定框 |
| [KO](ko.png) | 第 472 帧，P2 生命 0，P1 获胜 |
| [重赛](rematch.png) | 帧数回到 0，双方恢复 1000 生命 |

结构化记录见 [capture.json](capture.json)。测试脚本为 `tests/capture_evidence.gd`，截图来自与本文件一起提交的项目源码；Git 历史保留对应版本。

## 重现

在具备显示服务的机器上，从项目根目录运行：

```sh
godot --path . --script res://tests/capture_evidence.gd
```

脚本会将 PNG 与记录写入本目录。它拒绝 headless 显示驱动，避免将无渲染检查当成画面证据。通常约十秒内完成；软件渲染器首次启动可能较慢。

`tests/run_checks.py` 另行检查战斗、输入训练、30/144 渲染 FPS 下的物理帧输入、真实场景伤害与 KO、重赛和训练自动重置。截图与这些自动检查的作用不同。

## 尚未验证

- Windows 实机运行、图形驱动和键盘布局。
- 实体手柄、实际 USB 断连重连、输入延迟和两人同键盘的硬件冲突。
- 正式美术、音效、联网及发行构建。

脚本输入和合成控制器事件通过，不代表以上实体设备项目已验收。Windows 本地检查步骤见 [运行说明](../windows-review.md)。
