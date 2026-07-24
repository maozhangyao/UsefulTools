# sftpUp — SFTP 上传工具

## 概述

`sftpUp` 是一个轻量级的 .NET 6 控制台程序，用于将本地文件或目录中的文件批量上传至 SFTP 服务器，并保持本地目录层级结构。

## 使用前提

- 目标环境已安装 **.NET 6 Runtime**（[下载地址](https://dotnet.microsoft.com/download/dotnet/6.0)）
- 具备目标 SFTP 服务器的连接信息（地址、端口、用户名、密码）

## 命令行参数

| 参数 | 必需 | 说明 |
|------|------|------|
| `-host` | 是 | SFTP 服务器地址（IP 或域名） |
| `-port` | 否 | SFTP 端口号，默认 `22` |
| `-user` | 是 | SFTP 登录用户名 |
| `-pwd` | 是 | SFTP 登录密码 |
| `-local` | 是 | 本地文件路径 **或** 目录路径 |
| `-remote` | 是 | SFTP 目标目录 |
| `-recursion` | 否 | 递归上传子目录中的文件（仅 `-local` 为目录时有效） |
| `-force` | 否 | 覆盖 SFTP 服务器上已存在的文件 |

> **注意**：参数名不区分大小写，例如 `-host` 和 `-HOST` 效果相同。

## 使用方法

### 上传单个文件

```bash
sftpUp -host 192.168.1.100 -user admin -pwd 123456 -local D:\data\file.txt -remote /upload
```

### 上传目录所有直接子文件（不递归）

```bash
sftpUp -host 192.168.1.100 -user admin -pwd 123456 -local D:\data -remote /upload
```

### 递归上传子目录

```bash
sftpUp -host 192.168.1.100 -user admin -pwd 123456 -local D:\data -remote /upload -recursion
```

### 强制覆盖远程文件

```bash
sftpUp -host 192.168.1.100 -user admin -pwd 123456 -local D:\data -remote /upload -force
```

### 递归 + 强制覆盖

```bash
sftpUp -host 192.168.1.100 -user admin -pwd 123456 -local D:\data -remote /upload -recursion -force
```

### 指定非默认端口

```bash
sftpUp -host example.com -port 2222 -user joe -pwd secret -local D:\project\src -remote /backup -recursion -force
```

## 行为说明

### 目录层级映射

`-local` 为目录时，本地路径与远程路径的对应关系如下（假定 `-local D:\sftp_source`、`-remote /`）：

| 本地文件 | 远程路径 |
|---------|---------|
| `D:\sftp_source\file001.txt` | `/file001.txt` |
| `D:\sftp_source\2026-06\file011.txt` | `/2026-06/file011.txt` |
| `D:\sftp_source\2026-06\0613\file111.txt` | `/2026-06/0613/file111.txt` |

`-local` 为单个文件时（假定 `-local D:\data\myfile.txt -remote /upload`），上传至 `/upload/myfile.txt`。

### 递归控制

- `-local` 为**文件**时：`-recursion` 参数无意义，始终只上传该文件。
- `-local` 为**目录**时：
  - **不加 `-recursion`**：只上传目录的**直接子文件**，不进入子目录。
  - **加 `-recursion`**：递归扫描所有子目录，将文件按原层级结构上传。

### 覆盖控制

- **不加 `-force`**：上传前检查远程文件是否存在，若已存在则**跳过**，输出 `[跳过]` 信息。
- **加 `-force`**：远程文件已存在时仍然**覆盖**上传。

### 目录自动创建

`-remote` 路径及文件所在的远程子目录如果不存在，工具会自动逐层创建。

### 上传进度

每个文件上传时显示文件大小（KB），大文件（>100KB）实时刷新进度：

```
[上传] "file001.txt" (1.0 KB) -> /file001.txt
[上传] "largefile.iso" (51200.0 KB) ... 52428800/26214400/50%
```

进度行在同一行通过 `\r` 原地刷新，不会刷屏。

### 上传统计

上传结束后输出统计摘要：

```
==============================================
  上传完成
  成功: 5  跳过: 2  失败: 0
  创建远程目录: 3 个
==============================================
```

## 错误处理

工具对以下常见问题会给出明确的中文错误提示并退出：

| 场景 | 提示 |
|------|------|
| 缺少必需参数 | `[错误] 缺少必需参数: -host, -user` |
| 本地路径不存在 | `[错误] 本地路径不存在: "D:\notexist"` |
| 参数值缺失 | `[错误] 参数 "-host" 缺少值。` |
| 端口无效 | `[错误] -port 参数值无效，必须为 1-65535 之间的整数。` |
| 认证失败 | `[错误] SFTP 认证失败，请检查用户名和密码。` |
| 连接异常 | `[错误] SFTP 连接异常: ...` |
| 单个文件上传失败 | `[错误] 文件上传失败: "..."`（继续处理其余文件） |

## 构建方法

```bash
dotnet build
```

发布为单文件可执行文件：

```bash
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

输出文件位于 `sftpUp\bin\Release\net6.0\win-x64\publish\`
