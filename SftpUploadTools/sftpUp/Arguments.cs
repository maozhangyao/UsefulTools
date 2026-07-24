using System.Reflection;

namespace sftpUp;

/// <summary>
/// 命令行参数模型，解析并验证用户输入的所有参数。
/// </summary>
internal class Arguments
{
    // ---- 必需参数 ----
    public string Host { get; private set; } = null!;
    public int Port { get; private set; }
    public string Username { get; private set; } = null!;
    public string Password { get; private set; } = null!;

    /// <summary>本地路径，可能是文件或目录。</summary>
    public string LocalPath { get; private set; } = null!;

    /// <summary>SFTP 远程目标目录。</summary>
    public string RemoteDir { get; private set; } = null!;

    // ---- 可选参数 ----
    public bool Recursion { get; private set; }
    public bool Force { get; private set; }

    /// <summary>-local 传入的是否为单个文件。</summary>
    public bool IsFile { get; private set; }

    private Arguments() { }

    /// <summary>
    /// 从命令行 args 中解析参数。
    /// 格式: sftpUp -host <host> [-port <port>] -user <username> -pwd <password> -local <path> -remote <dir> [-recursion] [-force]
    /// -local 可以是单个文件路径或目录路径。
    /// </summary>
    public static Arguments Parse(string[] args)
    {
        if (args.Length == 0)
        {
            PrintUsage();
            Environment.Exit(1);
        }

        var result = new Arguments
        {
            Port = 22,
            Recursion = false,
            Force = false
        };

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i].ToLowerInvariant())
            {
                case "-host":
                    result.Host = GetValueOrExit(args, ref i, "-host");
                    break;
                case "-port":
                    var portStr = GetValueOrExit(args, ref i, "-port");
                    if (!int.TryParse(portStr, out var port) || port < 1 || port > 65535)
                    {
                        Console.Error.WriteLine("[错误] -port 参数值无效，必须为 1-65535 之间的整数。");
                        Environment.Exit(1);
                    }
                    result.Port = port;
                    break;
                case "-user":
                    result.Username = GetValueOrExit(args, ref i, "-user");
                    break;
                case "-pwd":
                    result.Password = GetValueOrExit(args, ref i, "-pwd");
                    break;
                case "-local":
                    result.LocalPath = GetValueOrExit(args, ref i, "-local");
                    break;
                case "-remote":
                    result.RemoteDir = GetValueOrExit(args, ref i, "-remote");
                    break;
                case "-recursion":
                    result.Recursion = true;
                    break;
                case "-force":
                    result.Force = true;
                    break;
                default:
                    Console.Error.WriteLine($"[错误] 无法识别的参数: \"{args[i]}\"");
                    PrintUsage();
                    Environment.Exit(1);
                    break;
            }
        }

        // 校验必需参数
        var missing = new List<string>();
        if (string.IsNullOrWhiteSpace(result.Host)) missing.Add("-host");
        if (string.IsNullOrWhiteSpace(result.Username)) missing.Add("-user");
        if (string.IsNullOrWhiteSpace(result.Password)) missing.Add("-pwd");
        if (string.IsNullOrWhiteSpace(result.LocalPath)) missing.Add("-local");
        if (string.IsNullOrWhiteSpace(result.RemoteDir)) missing.Add("-remote");

        if (missing.Count > 0)
        {
            Console.Error.WriteLine($"[错误] 缺少必需参数: {string.Join(", ", missing)}");
            PrintUsage();
            Environment.Exit(1);
        }

        // 判断 -local 是文件还是目录
        if (File.Exists(result.LocalPath))
        {
            result.IsFile = true;
        }
        else if (Directory.Exists(result.LocalPath))
        {
            result.IsFile = false;
            // 目录路径标准化为带结尾分隔符的格式
            result.LocalPath = Path.GetFullPath(result.LocalPath).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        }
        else
        {
            Console.Error.WriteLine($"[错误] 本地路径不存在: \"{result.LocalPath}\"");
            Console.Error.WriteLine($"      请确认该路径是有效的文件或目录。");
            Environment.Exit(1);
        }

        // 标准化远程目录路径
        result.RemoteDir = result.RemoteDir.Replace('\\', '/').TrimEnd('/');
        if (result.RemoteDir.Length == 0)
            result.RemoteDir = "/";

        return result;
    }

    /// <summary>
    /// 获取当前位置的参数值，如果不存在则报错退出。
    /// </summary>
    private static string GetValueOrExit(string[] args, ref int i, string paramName)
    {
        if (i + 1 >= args.Length || args[i + 1].StartsWith("-"))
        {
            Console.Error.WriteLine($"[错误] 参数 \"{paramName}\" 缺少值。");
            Environment.Exit(1);
        }
        return args[++i];
    }

    private static void PrintUsage()
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "1.0.0";
        Console.Error.WriteLine($@"
sftpUp v{version} - SFTP 上传工具
==================================================
用法: sftpUp -host <host> [-port <port>] -user <username> -pwd <password>
             -local <path> -remote <dir> [-recursion] [-force]

必需参数:
  -host      SFTP 服务器地址（IP 或域名）
  -user      SFTP 登录用户名
  -pwd       SFTP 登录密码
  -local     本地文件路径 或 目录路径
  -remote    SFTP 目标目录

可选参数:
  -port      SFTP 端口号（默认: 22）
  -recursion 递归上传子目录中的文件（仅 -local 为目录时有效）
  -force     覆盖 SFTP 服务器上已存在的文件

示例:
  上传单个文件:      sftpUp -host 192.168.1.100 -user admin -pwd 123456 -local D:\data\file.txt -remote /upload
  上传目录所有文件:  sftpUp -host 192.168.1.100 -user admin -pwd 123456 -local D:\data -remote /upload
  递归 + 覆盖:      sftpUp -host 192.168.1.100 -port 2222 -user joe -pwd secret -local ./src -remote /backup -recursion -force
");
    }
}
