# SFTP Upload Script 使用手册

## 概述

`sftp_upload.ps1` 是一个 PowerShell 脚本，用于将本地文件通过 SFTP 协议上传到远程服务器。基于 Windows 内置 OpenSSH 客户端（`sftp.exe`），**零依赖**，无需安装任何第三方库。

---

## 环境要求

- Windows 10 / Windows Server 2019 或更高版本（自带 OpenSSH Client）
- PowerShell 5.1 或更高版本

---

## 参数说明

| 参数 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `-SourceFile` | 是 | string | 本地源文件的完整路径 |
| `-RemotePath` | 是 | string | 远程 SFTP 服务器上的目标路径（含文件名） |
| `-Server` | 是 | string | SFTP 服务器地址（IP 或域名） |
| `-Username` | 是 | string | SFTP 登录用户名 |
| `-Password` | 否 | string | SFTP 登录密码（与 `-SshKeyPath` 二选一） |
| `-SshKeyPath` | 否 | string | SSH 私钥文件路径（与 `-Password` 二选一） |
| `-Port` | 否 | int | SFTP 端口号，默认 `22` |

---

## 使用示例

### 示例 1：密码认证上传

```powershell
.\sftp_upload.ps1 `
    -SourceFile "D:\data\report_20240714.csv" `
    -RemotePath "/incoming/report_20240714.csv" `
    -Server "192.168.1.100" `
    -Username "ftpuser" `
    -Password "MyP@ssw0rd"
```

### 示例 2：SSH 密钥认证上传

```powershell
.\sftp_upload.ps1 `
    -SourceFile "D:\backup\db_dump.sql.gz" `
    -RemotePath "/backups/db_dump.sql.gz" `
    -Server "sftp.example.com" `
    -Port 2222 `
    -Username "backup_user" `
    -SshKeyPath "C:\Users\admin\.ssh\id_rsa"
```

### 示例 3：上传到自定义端口

```powershell
.\sftp_upload.ps1 `
    -SourceFile ".\test.txt" `
    -RemotePath "/upload/test.txt" `
    -Server "10.0.0.50" `
    -Port 2222 `
    -Username "deploy" `
    -Password "deploy123"
```

---

## 说明

脚本完全基于 Windows 内置的 `sftp.exe`（OpenSSH Client），无需任何额外安装或下载。

> 密码认证通过 `SSH_ASKPASS` 机制实现：脚本将密码写入临时文件，创建 bat 脚本读取并输出密码，设置环境变量 `SSH_ASKPASS_REQUIRE=force` 强制调用。临时文件在上传完成后自动清除。

---

## 常见错误处理

| 错误信息 | 原因 | 解决办法 |
|----------|------|----------|
| `Source file not found: xxx` | 指定的源文件不存在 | 检查 `-SourceFile` 路径是否正确 |
| `SSH key file not found: xxx` | SSH 密钥文件不存在 | 检查 `-SshKeyPath` 路径是否正确 |
| `sftp failed with exit code 1` | 认证失败或远程路径错误 | 检查认证信息及远程目录权限 |
| `No connection could be made because the target machine actively refused it` | 服务器端口未开放 | 确认 `-Port` 和 SFTP 服务是否正常运行 |
| `Authentication of SSH session failed` | 用户名/密码错误 | 检查认证信息 |
| `Permission denied` | 远程目录无写入权限 | 检查远程目录权限 |

---

## 脚本工作流程

```
[用户输入参数]
      │
      ▼
┌─ 检查源文件是否存在 ── 否 ──→ 报错退出
      │ 是
      ▼
┌─ 生成 sftp batch 命令（mkdir + put）
      │
      ▼
┌─ 密码认证？──── 是 ──→ 创建临时密码文件 + askpass bat
      │ 否                    │
      ▼                       ▼
┌─ 调用 sftp.exe -b batchfile ──┐
      │                           │
      ▼                           ▼
┌─ 清理临时文件
      │
      ▼
  输出 "Upload complete!" 或报错退出
```

---

## 进阶用法

### 在批处理中调用

```batch
@echo off
powershell -ExecutionPolicy Bypass -File "C:\scripts\sftp_upload.ps1" ^
    -SourceFile "C:\data\file.txt" ^
    -RemotePath "/upload/file.txt" ^
    -Server "192.168.1.100" ^
    -Username "user" ^
    -Password "pass"
```

### 与任务计划程序集成

1. 打开「任务计划程序」
2. 创建基本任务 → 触发器（按需设置，如每天凌晨 2 点）
3. 操作选择「启动程序」
   - 程序：`powershell.exe`
    - 参数：`-ExecutionPolicy Bypass -File "D:\scripts\sftp_upload.ps1" -SourceFile "..." -RemotePath "..." -Server "..." -Username "..." -Password "..."`
