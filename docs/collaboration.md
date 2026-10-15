# 协作、验证与交付

## 单一项目根

GitHub 仓库 `TIAN-sign/re02` 是源码与项目文档的唯一来源。克隆后的根目录就是项目根；不嵌套另一套游戏工程，也不把 ZIP 包、环境目录或其他项目并入仓库。

当前结构：

```text
README.md                       当前状态与本地审核步骤
AGENTS.md                       代理工作约定
docs/project-scope.md            范围、待定事项与交付阶段
docs/collaboration.md            协作与验证约定
.gitignore                      本地文件与生成物排除规则
.github/workflows/repository-checks.yml
project.godot                   Godot 4.6.3 项目入口
scenes/                         主场景
presentation/                   驱动、绘制、HUD
shared/                         共享接口与常量
combat/                         纯战斗模拟与模块测试
input/                          输入、历史与模块测试
training/                       训练输入覆盖
tests/                          整合检查与实际视口采集
diyide                          原有占位文件，保留原样
```

当前采用 Godot 4.6.3，原始脚本及 `.uid` 跟踪到 Git；`.godot/` 生成缓存不提交。只有这一套游戏工程。

## 分支与唯一写者

- `main`：经过审核的基线。
- `chore/init-fighter`：已合并的初始化分支。
- `feat/playable-slice`：首个可玩版本集成分支，由整合者合入战斗与输入作者的独立提交。
- 后续使用 `feat/<topic>`、`fix/<topic>` 或 `docs/<topic>` 等短期分支。
- 每批任务先明确唯一写者、基准 SHA、负责路径和交付目标。其他研究线程只提供结论，不直接改同一工作区。
- 如确需并行实现，每位写者使用自己的分支和工作目录；共享配置由整合者修改，按依赖顺序合并 PR。

不以多个 ZIP 作为接入来源。临时参考内容必须先核对来源，只将需要的改动通过 Git 提交整合。

## PR 整合

1. 从已核实的远端基线建立工作分支，保留现有历史和无关文件。
2. 修改后先审查 diff、运行对应检查，再明确列出路径提交。
3. 推送工作分支，核对远端 SHA，建立指向 `main` 的 PR。
4. PR 说明具体变化、验证结果、已知限制以及本地审核办法。
5. 审核者按提交 SHA 拉取检查，确认后通过 GitHub 合并；不自动合并或强推。

这是一项工作约定，不代表 GitHub 分支保护、必需检查或审批规则已配置。

## 最小持续检查

`Repository checks` 工作流在 PR 和推送 `main` 时运行：

- 以只读仓库权限检出代码。
- 使用 `git diff --check` 检查本次变化的空白错误与冲突标记。
- 下载 Godot 4.6.3 官方 Linux 二进制并核验固定 SHA-256。
- 执行 `tests/run_checks.py`：导入解析、战斗、输入训练、真实 InputMap 物理帧、30/144 渲染 FPS 下的输入检查、完整场景整合与启动。

这些自动检查包含游戏逻辑，但不验证 Windows 实机和实体手柄；工作流能否执行仍受仓库 Actions 设置影响。提交前还需人工审查暂存区文件列表与内容，确认没有私人数据、凭据或无关项目文件。`.gitignore` 只防止部分文件被意外加入，不能替代审查。

后续测试优先覆盖会影响玩法的输入、状态转换、命中结算和胜负规则，避免仅为文档增加测试。渲染证据使用真实 Godot 视口单独采集，见 `docs/evidence/`。

## 可审核版本与本地运行

- 每次交付提供仓库地址、PR、分支、完整 commit SHA、实际验证结果和未完成项。
- 分支用于协作，commit SHA 用于固定审核版本。正式可玩里程碑才考虑打版本标签；本次不创建发布包或标签。
- 首次拉取和后续更新命令见根目录 `README.md`。需要复核旧版本时，在工作区干净的前提下执行 `git fetch origin`，再 `git switch --detach <完整提交SHA>`。
- 当前可在 Godot 4.6.3 导入 `project.godot` 后按 F5 运行，或执行 `godot --path .`。操作方法与一局验收见 `docs/windows-review.md`。
- 云端的本地提交、远端推送、CI 通过和可玩验收是不同状态，应分别报告。
