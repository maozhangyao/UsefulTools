using sftpUp;

// ---- 入口点 ----
// 解析命令行参数
var arguments = Arguments.Parse(args);

// 执行上传
using var uploader = new SftpUploader(arguments);
uploader.Run();
