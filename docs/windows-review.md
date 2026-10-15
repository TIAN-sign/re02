# Windows 本地运行与审核

运行工具为 **Godot 4.6.3 Standard**（非 .NET 版）。本项目不依赖插件或后台服务。

## 拉取指定版本

```powershell
git clone --branch feat/playable-slice https://github.com/TIAN-sign/re02.git fighter
cd fighter
git rev-parse HEAD
```

将完整 SHA 与交付记录对照；需要固定审核版本时，执行 `git switch --detach <完整SHA>`。已经克隆的工作区先保存自己的修改，再 `git fetch origin` 并切换指定版本。不要用 ZIP 覆盖项目。

## 启动

在 Godot 项目管理器中导入根目录 `project.godot`，按 F6 运行当前场景或 F5 运行整个项目。也可以使用 PowerShell，按实际路径替换引擎位置：

```powershell
& 'C:\Tools\Godot\Godot_v4.6.3-stable_win64.exe' --path .
```

项目设为 Compatibility 渲染、1280×720、每秒 60 次战斗更新。渲染帧率不改变战斗步长。运行时若出现 `WAITING FOR MODULES`，说明当前拉取的是尚未整合完成的中间版本，不能视作可玩交付。

## 操作

| 操作 | P1 | P2 | 对应玩家的手柄 |
| --- | --- | --- | --- |
| 移动 | A / D | 左 / 右 | 左摇杆或方向键 |
| 跳跃 / 蹲下 | W / S | 上 / 下 | 下方向蹲下；南侧键 A 跳跃 |
| 轻击 / 重击 / 投技 | J / K / L | 小键盘 1 / 2 / 3 | 西侧 X / 北侧 Y / 东侧 B |
| 防御 | U | 小键盘 0 | 左肩键 LB |

首两个连接的手柄依次分配 P1、P2。键盘仍可同时使用；使用手柄无需额外输入服务。键盘有按键冲突时优先使用两个手柄。P2 攻击使用小键盘，不是主键区数字。

- F1：切换本地对战 / 训练，并重置本局。
- F2：显示伤害框（红）与受击框（绿）。
- F3：显示逐帧输入历史，`L/H/T/G` 分别为轻击、重击、投技、防御。
- F4：循环训练假人模式。
- R / 手柄 Back：重赛。
- Escape / 手柄 Start：暂停、继续。
- 左键可点击屏幕顶部模式、判定框、输入历史和 Restart 按钮。

## 人工验收

1. 双方移动、跳跃、蹲下，确认不能越出擂台。
2. 接近后测试轻击、重击、防御与投技，观察生命条和状态。
3. 测试轻击衔接重击，观察连击数；打开 F2 比较启动、有效与恢复期间的判定框。
4. 攻击至 KO，确认胜者提示、停止结算，再按 R 重赛。
5. 按 F1 进入训练，使用 F4 切换假人行为；确认 F3 历史和 F2 判定框显示，训练 KO 后自动重置。
6. 分别验证键盘、两个手柄和手柄断开重连。记录设备型号与实际结果。

无窗口自动检查不能替代这些画面、手感和实际设备验收。请将检查版本的 SHA 与截图一并记录。

## 自动整合检查

真实模块合入后执行：

```powershell
& 'C:\Tools\Godot\Godot_v4.6.3-stable_win64.exe' --headless --path . --editor --quit
& 'C:\Tools\Godot\Godot_v4.6.3-stable_win64.exe' --headless --path . --script res://tests/integration_smoke.gd
```

整合测试直接使用生产入口与真实模块，覆盖 60 Hz 驱动、移动、暂停、伤害、KO、重赛、训练入口、历史与显示开关。没有模块时测试会失败，不会用替身判为通过。
