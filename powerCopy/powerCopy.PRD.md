# powerCopy 需求文档 (PRD)

## 1. 项目背景

在日常开发/运维工作中，经常需要将某个源目录下的文件按原有层级结构批量复制到目标目录中。有两种常见场景：

- **场景 A**：直接以指定目录为根，复制其下所有内容（保留相对路径）
- **场景 B**：以指定目录下的一级子目录为根，分别复制每个子目录的内容（每个子目录各自保留相对路径）

现有方案（手动复制、常规 `Copy-Item`）还存在长路径限制（Windows 默认 MAX_PATH 为 260 字符）等问题。

因此需要一个专用 PowerShell 脚本，通过参数切换两种模式，并支持超长路径。

---

## 2. 功能需求

### FR-01：指定源路径和目标路径

- 用户必须通过参数指定源文件夹路径（`-Source`）和目标文件夹路径（`-Destination`）
- 支持绝对路径和相对路径
- 路径分隔符兼容 `\` 和 `/`

### FR-02：两种处理模式（通过参数切换）

通过 `-FromSubDirs` 开关参数切换两种模式：

**模式 A（默认）—— 以源文件夹本身为根**

- 递归处理源文件夹下所有文件及子文件夹
- 路径从源文件夹开始计算

```
源: D:/rootDir/file.txt          →  D:/destDir/file.txt
源: D:/rootDir/sub/d.txt         →  D:/destDir/sub/d.txt
```

**模式 B（`-FromSubDirs`）—— 以源文件夹的直接子文件夹为根**

- 遍历源文件夹的每个直接子文件夹，分别作为处理单元
- 路径从子文件夹开始计算（子文件夹本身不包含在路径中）

```
源: D:/rootDir/dir001/file.txt   →  D:/destDir/file.txt
源: D:/rootDir/dir001/sub/d.txt  →  D:/destDir/sub/d.txt
源: D:/rootDir/dir002/data.log   →  D:/destDir/data.log
```

### FR-03：递归控制

- 默认行为：**递归**处理（进入子目录）
- 提供 `-NoRecurse` 开关参数：不递归，仅处理所选模式根目录下的直接文件
  - 模式 A：仅复制源文件夹根目录下的直接文件，跳过子文件夹
  - 模式 B：仅复制子文件夹根目录下的直接文件，跳过更深层子文件夹

### FR-04：保留相对层级关系

- 无论哪种模式，相对路径均从**处理根目录**开始计算
- 示例：

```
# 模式 A（默认）：根目录 = 源文件夹
源: D:/rootDir/a.txt          →  目标: D:/destDir/a.txt
源: D:/rootDir/x/y.txt        →  目标: D:/destDir/x/y.txt

# 模式 B（-FromSubDirs）：根目录 = 各子文件夹
源: D:/rootDir/dirA/a.txt     →  目标: D:/destDir/a.txt
源: D:/rootDir/dirA/x/y.txt   →  目标: D:/destDir/x/y.txt
源: D:/rootDir/dirB/b.txt     →  目标: D:/destDir/b.txt
```

### FR-05：文件覆盖控制

- 默认行为：目标文件已存在时**覆盖**
- 提供 `-NoClobber` 开关参数：启用时跳过已存在的文件，不覆盖

### FR-06：预览模式

- 提供 `-WhatIf` 开关参数：仅显示将要复制的文件列表，不实际执行复制操作

---

## 3. 非功能需求

### NFR-01：长路径支持

- 必须支持路径长度超过 260 字符的文件
- 文件枚举、目录创建、文件复制三个环节均需绕过 MAX_PATH 限制
- 方案：使用 Win32 API（`CreateDirectoryW` / `CopyFileW`）+ `\\?\` 扩展路径前缀

### NFR-02：错误隔离

- 单个子文件夹或单个文件的处理失败不应中断整体流程
- 每个失败单独报告错误信息

### NFR-03：用户反馈

- 每个文件操作需要给出明确的状态标记（成功/覆盖/跳过/失败）
- 最终汇总统计（复制数、跳过数、错误数）

---

## 4. 边界与约束

| 边界 | 说明 |
|------|------|
| 操作系统 | Windows（依赖 Win32 API） |
| PowerShell | ≥ 5.1 |
| 执行策略 | 允许执行 `.ps1` 脚本 |
| 源文件夹为空（或无子文件夹） | 正常退出，提示无内容可复制 |
| 源文件夹不存在 | 报错退出 |
| 目标文件夹不存在 | 自动创建 |
| 网络路径 | 支持 UNC 路径（自动转换为 `\\?\UNC\`） |

---

## 5. 交互示例

```powershell
# 模式 A：以源文件夹为根，递归复制
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir

# 模式 B：以子文件夹为根，递归复制
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -FromSubDirs

# 不递归（仅处理根目录下的直接文件）
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -NoRecurse
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -FromSubDirs -NoRecurse

# 禁止覆盖
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -NoClobber

# 预览模式
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -WhatIf

# 组合使用
.\powerCopy.ps1 D:\rootDir D:\destDir -FromSubDirs -NoRecurse -NoClobber -WhatIf
```

---

## 6. 输入/输出

### 输入

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `-Source` | string | 是 | — | 源文件夹路径（位置 0） |
| `-Destination` | string | 是 | — | 目标文件夹路径（位置 1） |
| `-FromSubDirs` | switch | 否 | $false | 以子文件夹为根处理（模式 B），默认以源文件夹为根（模式 A） |
| `-NoRecurse` | switch | 否 | $false | 不递归，仅处理根目录下的直接文件 |
| `-NoClobber` | switch | 否 | $false | 不覆盖已有文件 |
| `-WhatIf` | switch | 否 | $false | 预览模式 |

### 输出

控制台输出格式示例：

```
# 模式 A（默认）：以源文件夹为根
===== powerCopy =====
  Source      : D:\rootDir
  Destination : D:\destDir
  FromSubDirs : False
  NoRecurse   : False
  NoClobber   : False

[OK]   file.txt
[OK]   sub/file.txt
[OVR]  sub/nested/data.log

===== Complete =====
  Copied  : 3
  Skipped : 0
  Errors  : 0
```

```
# 模式 B（-FromSubDirs）：以子文件夹为根
===== powerCopy =====
  Source      : D:\rootDir
  Destination : D:\destDir
  FromSubDirs : True
  NoRecurse   : False
  NoClobber   : False

--- [dir001] ---
[OK]   file.txt
[OK]   sub/data.log

--- [dir002] ---
[FAIL] config.ini : CopyFileW failed (error 5)

===== Complete =====
  Copied  : 2
  Skipped : 0
  Errors  : 1
```

---

## 7. 验收标准

| # | 验收条件 | 对应需求 |
|---|---------|---------|
| 1 | 默认模式（不指定 `-FromSubDirs`）以源文件夹为根，递归复制，保留完整相对路径 | FR-02, FR-03, FR-04 |
| 2 | 模式 B（`-FromSubDirs`）以每个直接子文件夹为根，递归复制，路径从子文件夹开始 | FR-02, FR-03, FR-04 |
| 3 | 加 `-NoRecurse` 时两种模式均不递归，仅处理根目录下的直接文件 | FR-03 |
| 4 | 不加 `-NoClobber` 时同名文件被覆盖 | FR-05 |
| 5 | 加 `-NoClobber` 时同名文件被跳过并提示 | FR-05 |
| 6 | `-WhatIf` 模式下只打印不复制 | FR-06 |
| 7 | 超过 260 字符路径的文件也能正常复制 | NFR-01 |
| 8 | 单个文件失败不影响其余文件 | NFR-02 |
