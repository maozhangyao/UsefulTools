# powerCopy 使用手册

## 概述

`powerCopy.ps1` 是一个 PowerShell 脚本，用于将源目录中的文件按原有层级结构批量复制到目标目录。支持两种处理模式和超长路径（突破 Windows 260 字符 MAX_PATH 限制）。

---

## 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `-Source` | string | 是 | — | 源文件夹路径（位置 0，可作为第一个参数直接传入） |
| `-Destination` | string | 是 | — | 目标文件夹路径（位置 1） |
| `-FromSubDirs` | switch | 否 | `$false` | **模式 B**：以源文件夹的直接子文件夹为根处理；默认是**模式 A**：以源文件夹本身为根 |
| `-NoRecurse` | switch | 否 | `$false` | 不递归，仅处理根目录下的直接文件（跳过子文件夹） |
| `-NoClobber` | switch | 否 | `$false` | 目标文件已存在时跳过，不覆盖 |
| `-WhatIf` | switch | 否 | `$false` | 预览模式，只显示将要复制的文件列表，不实际执行 |

---

## 两种处理模式

### 模式 A（默认）：以源文件夹本身为根

递归处理源文件夹下所有文件及子文件夹，路径从源文件夹开始计算。

```
源: D:\rootDir\file.txt          →  D:\destDir\file.txt
源: D:\rootDir\sub\d.txt         →  D:\destDir\sub\d.txt
```

### 模式 B（`-FromSubDirs`）：以子文件夹为根

遍历源文件夹的每个直接子文件夹，分别作为处理单元。路径从子文件夹开始计算（子文件夹本身不包含在路径中）。

```
源: D:\rootDir\dir001\file.txt   →  D:\destDir\file.txt
源: D:\rootDir\dir001\sub\d.txt  →  D:\destDir\sub\d.txt
源: D:\rootDir\dir002\data.log   →  D:\destDir\data.log
```

---

## 使用示例

### 基本用法

```powershell
# 模式 A：以源文件夹为根，递归复制
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir

# 模式 B：以子文件夹为根，递归复制
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -FromSubDirs
```

### 不递归

```powershell
# 模式 A，仅复制源文件夹根目录下的直接文件
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -NoRecurse

# 模式 B，仅复制各子文件夹根目录下的直接文件
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -FromSubDirs -NoRecurse
```

### 文件覆盖控制

```powershell
# 禁止覆盖已有文件
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -NoClobber
```

### 预览模式

```powershell
# 只显示将复制的文件，不实际执行
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -WhatIf
```

### 组合使用

```powershell
.\powerCopy.ps1 D:\rootDir D:\destDir -FromSubDirs -NoRecurse -NoClobber -WhatIf
```

---

## 输出说明

```
===== powerCopy =====
  Source      : D:\rootDir
  Destination : D:\destDir
  FromSubDirs : True
  NoRecurse   : False
  NoClobber   : False

--- [dir001] ---
[OK]   file.txt
[OVR]  data.log
[SKIP] config.ini
[FAIL] bad.txt : CopyFileW failed (error 5)

===== Complete =====
  Copied  : 1
  Skipped : 1
  Errors  : 1
```

### 状态标记

| 标记 | 含义 |
|------|------|
| `[OK]` | 成功复制新文件 |
| `[OVR]` | 覆盖已有文件 |
| `[SKIP]` | 跳过已有文件（仅 `-NoClobber` 时出现） |
| `[FAIL]` | 复制失败（附带错误信息） |
| `[WhatIf]` | 预览模式，不会实际执行 |

---

## 超长路径支持

Windows 默认路径长度限制为 260 字符。本脚本通过 Win32 API + `\\?\` 扩展路径前缀突破该限制：

1. **文件枚举**：`[System.IO.Directory]::GetFiles()` 配合 `\\?\` 前缀递归扫描
2. **目录创建**：`kernel32!CreateDirectoryW` 配合 `\\?\` 前缀逐级创建
3. **文件复制**：`kernel32!CopyFileW` 配合 `\\?\` 前缀直接操作

支持 UNC 网络路径（自动转换为 `\\?\UNC\` 格式）。

---

## 注意事项

- 源文件夹不存在时报错退出（exit code 1）
- 目标文件夹不存在时自动创建（`-WhatIf` 模式下不创建）
- 路径分隔符兼容 `\` 和 `/`
- 支持绝对路径、相对路径、UNC 网络路径
- 单个文件/子文件夹处理失败不影响整体流程（错误隔离）
- 源文件夹为空或无子文件夹时正常退出，提示无内容可复制
- 使用 `-WhatIf` 时输出末尾会额外提示 `[WhatIf] mode finished. No files were copied.`

---

## 文件清单

```
powerCopy.ps1          - 主脚本
powerCopy_manual.md    - 本使用手册
test_powerCopy.ps1     - 测试脚本（16 个测试用例，25 项断言）
powerCopy.PRD.md       - 产品需求文档
```
