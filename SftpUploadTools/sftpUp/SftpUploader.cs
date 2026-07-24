using Renci.SshNet;

namespace sftpUp;

/// <summary>
/// SFTP 上传器，负责将本地文件按目录层级上传到 SFTP 服务器。
/// </summary>
internal class SftpUploader : IDisposable
{
    private readonly SftpClient _client;
    private readonly Arguments _args;
    // 本地基础目录（用于计算相对路径）
    private string _baseLocalDir = null!;

    // 上传统计
    public int UploadedCount { get; private set; }
    public int SkippedCount { get; private set; }
    public int FailedCount { get; private set; }
    public int CreatedDirCount { get; private set; }

    public SftpUploader(Arguments args)
    {
        _args = args;
        _client = new SftpClient(args.Host, args.Port, args.Username, args.Password);
        _client.ConnectionInfo.Timeout = TimeSpan.FromSeconds(30);
        _client.OperationTimeout = TimeSpan.FromSeconds(60);
        _client.KeepAliveInterval = TimeSpan.FromSeconds(30);
    }

    /// <summary>
    /// 执行上传流程：连接服务器、获取文件列表、逐个上传。
    /// </summary>
    public void Run()
    {
        try
        {
            Console.WriteLine($"[信息] 正在连接 SFTP 服务器 {_args.Host}:{_args.Port} ...");
            _client.Connect();
            Console.WriteLine("[信息] 连接成功。");

            EnsureRemoteDirectory(_args.RemoteDir);

            // 根据 -local 是文件还是目录获取文件列表
            var files = GetLocalFiles();
            if (files.Length == 0)
            {
                Console.WriteLine("[信息] 未找到任何文件，无需上传。");
                return;
            }

            Console.WriteLine($"[信息] 共发现 {files.Length} 个文件，开始上传...");

            foreach (var localFilePath in files)
            {
                try
                {
                    UploadFile(localFilePath);
                }
                catch (Exception ex)
                {
                    FailedCount++;
                    Console.Error.WriteLine($"[错误] 文件上传失败: \"{localFilePath}\"");
                    Console.Error.WriteLine($"      原因: {ex.Message}");
                }
            }

            PrintSummary();
        }
        catch (Renci.SshNet.Common.SshAuthenticationException)
        {
            Console.Error.WriteLine("[错误] SFTP 认证失败，请检查用户名和密码。");
            Environment.Exit(1);
        }
        catch (Renci.SshNet.Common.SshConnectionException ex)
        {
            Console.Error.WriteLine($"[错误] SFTP 连接异常: {ex.Message}");
            Console.Error.WriteLine($"      请检查服务器地址、端口以及网络连接是否正常。");
            Environment.Exit(1);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[错误] 程序运行异常: {ex.Message}");
            Console.Error.WriteLine(ex.StackTrace);
            Environment.Exit(1);
        }
        finally
        {
            if (_client.IsConnected)
                _client.Disconnect();
        }
    }

    /// <summary>
    /// 根据 -local 是文件还是目录获取待上传的文件列表。
    /// </summary>
    private string[] GetLocalFiles()
    {
        if (_args.IsFile)
        {
            _baseLocalDir = Path.GetDirectoryName(_args.LocalPath)!;
            return new[] { _args.LocalPath };
        }

        _baseLocalDir = _args.LocalPath;
        var searchOption = _args.Recursion ? SearchOption.AllDirectories : SearchOption.TopDirectoryOnly;
        return Directory.GetFiles(_args.LocalPath, "*", searchOption);
    }

    /// <summary>
    /// 上传单个文件，如果目标存在且未指定 -force 则跳过。
    /// 上传过程中通过 \r 在同一行刷新进度，避免刷屏。
    /// </summary>
    private void UploadFile(string localFilePath)
    {
        // 相对路径（相对于本地基础目录）
        var relativePath = localFilePath.Substring(_baseLocalDir.Length).TrimStart('\\', '/');
        // 远程完整路径
        var remoteFilePath = _args.RemoteDir + "/" + relativePath.Replace('\\', '/');

        // 确保远程父目录存在
        var remoteParentDir = Path.GetDirectoryName(remoteFilePath)!.Replace('\\', '/');
        EnsureRemoteDirectory(remoteParentDir);

        // 检查远程文件是否已存在
        if (!_args.Force && RemoteFileExists(remoteFilePath))
        {
            Console.WriteLine($"[跳过] \"{relativePath}\" (远程文件已存在)");
            SkippedCount++;
            return;
        }

        var fileInfo = new FileInfo(localFilePath);
        long totalBytes = fileInfo.Length;
        double sizeKB = totalBytes / 1024.0;

        // 大文件（>100KB）展示实时进度，小文件直接完成避免闪烁
        bool showProgress = totalBytes > 100 * 1024;

        Console.Write($"[上传] \"{relativePath}\" ({sizeKB:F1} KB) ... ");

        using (var fileStream = new FileStream(localFilePath, FileMode.Open, FileAccess.Read))
        {
            _client.UploadFile(fileStream, remoteFilePath, true, uploadedBytes =>
            {
                if (!showProgress || totalBytes <= 0) return;
                var percent = Math.Min(100, (int)(uploadedBytes * 100 / (ulong)totalBytes));
                Console.Write($"\r[上传] \"{relativePath}\" ({sizeKB:F1} KB) ... {totalBytes}/{uploadedBytes}/{percent}%");
            });
        }

        // 覆盖进度行，显示完成信息
        Console.Write($"\r[上传] \"{relativePath}\" ({sizeKB:F1} KB) -> {remoteFilePath}  ");
        Console.WriteLine();
        UploadedCount++;
    }

    private void EnsureRemoteDirectory(string remotePath)
    {
        if (string.IsNullOrWhiteSpace(remotePath) || remotePath == "/")
            return;

        remotePath = remotePath.Replace('\\', '/').TrimEnd('/');

        if (_client.Exists(remotePath))
            return;

        var parts = remotePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var current = "";
        foreach (var part in parts)
        {
            current += "/" + part;
            if (!_client.Exists(current))
            {
                _client.CreateDirectory(current);
                CreatedDirCount++;
                Console.WriteLine($"[创建目录] {current}");
            }
        }
    }

    private bool RemoteFileExists(string remotePath)
    {
        return _client.Exists(remotePath);
    }

    private void PrintSummary()
    {
        Console.WriteLine();
        Console.WriteLine("==============================================");
        Console.WriteLine("  上传完成");
        Console.WriteLine($"  成功: {UploadedCount}  跳过: {SkippedCount}  失败: {FailedCount}");
        Console.WriteLine($"  创建远程目录: {CreatedDirCount} 个");
        Console.WriteLine("==============================================");
    }

    public void Dispose()
    {
        _client?.Dispose();
    }
}
