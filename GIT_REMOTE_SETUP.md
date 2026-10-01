# Git Remote 与分支保护

当前仓库不配置 remote。本文不授权创建公网仓库；请由仓库所有者在 GitHub 上创建 **Private** repository 后执行。

```bash
git remote add origin git@github.com:OWNER/personal-health-os.git
git remote -v
git push -u origin main
git push -u origin feature/phase7-supervision
```

GitHub 设置：

1. 确认 repository visibility 为 Private，禁止提交 `.env`、`.p8`、数据库 dump、体检原文件或餐食照片。
2. 对 `main` 开启 branch protection：只能 PR 合并、至少 1 人审核、要求分支最新、禁止 force push 和 deletion。
3. 将以下 Actions 检查设为 required：`backend`、`backend-postgres`、`mobile-ios-primary`、`mobile-android-compat`。
4. 在 Actions 页手工检查首次运行；对 macOS iOS no-codesign 和 PostgreSQL restore drill 的结果不做本地推测。
5. 如使用 HTTPS remote，使用 GitHub CLI/系统凭据管理器，不把 PAT 写入 URL 或仓库文件。

如果已添加了错误的 origin，先使用 `git remote get-url origin` 确认目标，只在确认新的私有仓库 URL 后执行 `git remote set-url origin ...`。
