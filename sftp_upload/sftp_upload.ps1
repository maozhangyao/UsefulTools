param(
    [Parameter(Mandatory=$true)]
    [string]$SourceFile,

    [Parameter(Mandatory=$true)]
    [string]$RemotePath,

    [Parameter(Mandatory=$true)]
    [string]$Server,

    [Parameter(Mandatory=$true)]
    [string]$Username,

    [string]$Password,

    [string]$SshKeyPath,

    [int]$Port = 22
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SourceFile)) {
    Write-Error "Source file not found: $SourceFile"
    exit 1
}

# build sftp batch commands
$remoteDir = Split-Path -Path $RemotePath -Parent -ErrorAction Ignore
$batchLines = @()
if ($remoteDir -and $remoteDir -ne '.' -and $remoteDir -ne '') {
    $batchLines += "-mkdir $($remoteDir -replace '\\', '/')"
}
$batchLines += "put '$($SourceFile -replace "'", "''")' '$($RemotePath -replace '\\', '/')'"
$batchLines += "bye"

$batchFile = Join-Path $env:TEMP "sftp_batch_$PID.txt"
Set-Content -Path $batchFile -Value ($batchLines -join "`r`n") -Encoding ASCII

$sftpArgs = @("-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes")
if ($Port -ne 22) { $sftpArgs += "-o", "Port=$Port" }
if ($SshKeyPath) { $sftpArgs += "-o", "IdentityFile=$SshKeyPath" }
$sftpArgs += "-b", $batchFile
$sftpArgs += "$Username@$Server"

try {
    if ($Password) {
        # SSH_ASKPASS: 将密码写入临时文件，bat 从文件读取（避免转义问题）
        $pwdFile = Join-Path $env:TEMP "sftp_pass_$PID.txt"
        Set-Content -Path $pwdFile -Value $Password -NoNewline -Encoding ASCII

        $askpassBat = Join-Path $env:TEMP "sftp_askpass_$PID.bat"
        "@echo off
type `"$pwdFile`"" | Set-Content -Path $askpassBat -Encoding ASCII

        $env:SSH_ASKPASS = $askpassBat
        $env:SSH_ASKPASS_REQUIRE = "force"
    }

    & "sftp.exe" $sftpArgs
    $exitCode = $LASTEXITCODE
} finally {
    Remove-Item -Path $batchFile -Force -ErrorAction Ignore
    if ($askpassBat -and (Test-Path -LiteralPath $askpassBat)) {
        Remove-Item -Path $askpassBat -Force
    }
    if ($pwdFile -and (Test-Path -LiteralPath $pwdFile)) {
        Remove-Item -Path $pwdFile -Force
    }
    if ($Password) {
        $env:SSH_ASKPASS = $null
        $env:SSH_ASKPASS_REQUIRE = $null
    }
}

if ($exitCode -ne 0) {
    Write-Error "sftp failed with exit code $exitCode"
    exit $exitCode
}

Write-Host "Upload complete!" -ForegroundColor Green
