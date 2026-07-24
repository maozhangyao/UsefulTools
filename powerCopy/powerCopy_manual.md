# powerCopy 使用说明

## 概述

递归复制源文件夹下**所有子文件夹**的文件到目标文件夹，保留相对层级关系，支持超长路径（>260字符）。

## 适用场景

- 需要将多个子目录中的文件"摊平层级"但保留每个子目录内部的目录结构
- 源路径可能很长（超过 Windows 260字符 MAX_PATH 限制）

## 核心逻辑

```
源文件夹 D:/rootDir/
├── dirA/
│   ├── file1.txt        →  D:/destDir/file1.txt
│   └── sub/
│       └── file2.txt    →  D:/destDir/sub/file2.txt
├── dirB/
│   └── data.log         →  D:/destDir/data.log
└── rootFile.txt         ← 忽略（源文件夹根级文件不处理）
```

**关键规则**：路径层级从**被 copy 的子文件夹**开始计算，不是从源文件夹。

## 参数说明

| 参数 | 必填 | 说明 |
|------|------|------|
| `-Source` | 是 | 源文件夹路径（位置 0，可直接放第一个参数） |
| `-Destination` | 是 | 目标文件夹路径（位置 1） |
| `-NoClobber` | 否 | 开关，启用时不覆盖已存在的文件。默认覆盖。 |
| `-WhatIf` | 否 | 开关，预览模式，只显示将要 copy 的文件，不实际执行。 |

## 使用示例

```powershell
# 基本用法
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir

# 不覆盖已有文件
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -NoClobber

# 预览（不实际 copy）
.\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -WhatIf

# 使用位置参数（等效于第一种）
.\powerCopy.ps1 D:\rootDir D:\destDir
```

## 输出说明

| 标记 | 含义 |
|------|------|
| `[OK]` | 成功 copy 新文件 |
| `[OVR]` | 覆盖已有文件 |
| `[SKIP]` | 跳过已有文件（仅 `-NoClobber` 时出现） |
| `[FAIL]` | copy 失败 |
| `[WhatIf]` | 预览模式下的提示 |

## 超长路径支持

Windows 默认路径长度限制为 260 字符。本脚本通过以下方式突破该限制：

1. **文件枚举**：使用 `[System.IO.Directory]::GetFiles()` + `\\?\` 前缀递归扫描文件
2. **目录创建**：使用 `kernel32!CreateDirectoryW` + `\\?\` 前缀逐级创建目录
3. **文件复制**：使用 `kernel32!CopyFileW` + `\\?\` 前缀直接操作文件

这意味着即使源目录下有超过 260 字符路径的文件，也能正确处理。

## 内部实现

- `Add-Type` 编译 C# P/Invoke 代码，引入 `CreateDirectoryW` 和 `CopyFileW` Win32 API
- `ConvertToExtendedPath()`：将普通路径转换为 `\\?\` 前缀的扩展长度路径格式
- `Ensure-Directory()`：逐级创建目录，每级调用 `CreateDirectoryW`，遇 `ERROR_ALREADY_EXISTS` (183) 时跳过

## 文件清单

```
powerCopy.ps1         - 正式脚本
powerCopy_manual.md   - 本说明文件
test_powerCopy.ps1    - 测试脚本（含 6 个测试用例）
```

## 注意事项

- 目标文件夹不存在时会自动创建
- 脚本仅处理源文件夹的**直接子文件夹**，不处理源文件夹根目录下的文件
- 如有同名文件，默认覆盖（`-NoClobber` 可禁止覆盖）
- 不会递归处理子文件夹的文件夹作为新的源——只有源文件夹的 1 级子文件夹会被处理
- 使用 `Get-ChildItem -Directory` 获取子文件夹列表，不会因单个子文件夹枚举失败而中断整个流程
