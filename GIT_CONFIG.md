# LocalScroll-App Git 配置

**本文档位置**：`/Users/ipanda/Documents/Code/iosproject/LocalScroll_Xcode/GIT_CONFIG.md`

---

## 当前配置状态 ✅

```bash
Remote: origin = https://github.com/WYR186/LocalScroll-App.git
Branches:
  - main                 (App Store 稳定版)
  - ios-port-phases-2-7  (开发分支，当前活跃)

Status: 已与 GitHub 同步
```

验证配置：
```bash
cd /Users/ipanda/Documents/Code/iosproject/LocalScroll_Xcode
git remote -v
# 应显示：origin    https://github.com/WYR186/LocalScroll-App.git (fetch)
#         origin    https://github.com/WYR186/LocalScroll-App.git (push)
```

---

## 日常 Git 操作

### ✅ 推送当前分支
```bash
cd /Users/ipanda/Documents/Code/iosproject/LocalScroll_Xcode
git push origin ios-port-phases-2-7
```

### ✅ 推送所有分支
```bash
git push origin --all
```

### ✅ 创建新分支并推送
```bash
git checkout -b feature/new-feature
# ... 修改代码 ...
git add -A
git commit -m "Add new feature"
git push -u origin feature/new-feature
```

### ✅ 同步远程最新代码
```bash
git fetch origin
git pull origin <branch-name>
```

---

## ⚠️ 常见错误

### ❌ 错误：push 到了错误的仓库
**症状**：看到 commits 出现在 GitHub `localScroll` 仓库而不是 `LocalScroll-App`

**原因**：配置错误的 remote 或路径错误

**检查**：
```bash
pwd
# 应该显示：/Users/ipanda/Documents/Code/iosproject/LocalScroll_Xcode

git remote -v
# 应该显示：origin    https://github.com/WYR186/LocalScroll-App.git
#           （NOT localScroll.git）

git log -1 --oneline
# 确认这是 iOS App 的 commit
```

### ❌ 错误：在 localScroll_iOS 目录下尝试 push
**症状**：`fatal: not a git repository`

**原因**：`/project/localScroll_iOS` 不是独立 git 仓库，它是 `localScroll` 的子目录

**正确做法**：
```bash
cd /Users/ipanda/Documents/project/LocalScroll
git push origin main
```

---

## 核心规则（必读）

| 规则 | 说明 |
|------|------|
| 🔒 **push 前验证 remote** | `git remote -v` 必须显示 `LocalScroll-App.git` |
| 🔒 **push 前验证路径** | `pwd` 必须显示 `/Code/iosproject/LocalScroll_Xcode` |
| 🔒 **main 分支限定** | 仅用于 App Store 发布稳定版 |
| 🔒 **开发在分支** | 日常开发使用 `ios-port-phases-2-7` 或新建分支 |
| 🔒 **iOS Core 改动** | 通过 `/project/LocalScroll` 仓库推送（不在此目录） |

---

## 三个仓库的完整映射

详见：**`/Users/ipanda/Documents/GIT_REPOS_MAP.md`**

快速查询：
```bash
# iOS App（此目录）
cd /Users/ipanda/Documents/Code/iosproject/LocalScroll_Xcode
git push origin <branch>  # → GitHub: WYR186/LocalScroll-App

# Python + iOS Core（不同目录）
cd /Users/ipanda/Documents/project/LocalScroll
git push origin main  # → GitHub: WYR186/localScroll
```

---

## 最后检查清单 (每次 push 前)

- [ ] `pwd` 显示 `/Code/iosproject/LocalScroll_Xcode`
- [ ] `git remote -v` 显示 `LocalScroll-App.git`
- [ ] `git log -1` 确认是 iOS App 的 commit
- [ ] `git status` 确认改动已提交
- [ ] `git push origin <branch>` 执行 push
- [ ] 检查 GitHub `WYR186/LocalScroll-App` 确认 push 成功

---

**有疑问时**：查看 `/Users/ipanda/Documents/GIT_REPOS_MAP.md` 的完整说明。
