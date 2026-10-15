# 横版一对一格斗游戏

独立的街机式横版一对一格斗项目。采用原创角色、场景、音效与招式表现，不复制《街头霸王》的素材。

代码与文档以本仓库为唯一来源，通过云端 Git 开发、PR 审核和本地拉取保持一致。

## 当前状态

本次交付是项目初始化文档与仓库检查，尚无可运行的游戏。引擎、美术风格、目标平台与首版联网范围均未确定。

- [项目范围与待定事项](docs/project-scope.md)
- [协作、验证与版本交付约定](docs/collaboration.md)
- [代理工作约定](AGENTS.md)

根目录原有的 `diyide` 是简单 HTML 占位文件，保留原样，不作为游戏入口。

## 本地审核初始化版本

需要本地已有 Git；这一版本不需要安装引擎或依赖。首次拉取到新的目录：

```sh
git clone --branch chore/init-fighter https://github.com/TIAN-sign/re02.git fighter
cd fighter
git rev-parse HEAD
git diff --stat origin/main...HEAD
git diff --check origin/main...HEAD
git diff origin/main...HEAD
```

将 `git rev-parse HEAD` 的结果与交付记录中的完整 commit SHA 对照。检查期间如需固定版本，使用 `git switch --detach <完整提交SHA>`，其中占位符替换为实际值。

PR 合并后，在工作区干净时更新主分支：

```sh
git fetch origin
git switch main
git pull --ff-only origin main
```

若已有本地修改，先保存到自己的分支；不要使用强制重置覆盖。当前无游戏启动命令。首个实现 PR 必须补充精确的工具版本、安装与启动命令、操作按键和可玩验收步骤。
