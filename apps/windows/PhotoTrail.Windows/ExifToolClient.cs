using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace PhotoTrail.Windows;

public sealed class ExifToolClient(string executable, string? script = null)
{
    public async Task<string> RunAsync(IEnumerable<string> arguments, CancellationToken cancellation = default, TimeSpan? timeout = null, string? workingDirectory = null)
        => new UTF8Encoding(false,true).GetString(await RunBytesAsync(arguments,cancellation,timeout,workingDirectory));

    public async Task<byte[]> RunBytesAsync(IEnumerable<string> arguments, CancellationToken cancellation = default,
        TimeSpan? timeout = null, string? workingDirectory = null)
    {
        cancellation.ThrowIfCancellationRequested();
        var argumentList = arguments.ToArray();
        if (argumentList.Any(argument => argument.IndexOfAny(['\r', '\n', '\0']) >= 0))
            throw new ArgumentException("工具参数不能包含换行或NUL；多行元数据通过值文件传递。");
        var info = new ProcessStartInfo(executable)
        {
            UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = workingDirectory ?? "",
            RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
            StandardInputEncoding = new UTF8Encoding(false)
        };
        info.Environment["LC_ALL"] = "C";
        info.Environment["LC_CTYPE"] = "C";
        info.Environment["LANG"] = "C";
        if (script is not null) info.ArgumentList.Add(script);
        // ExifTool's UTF-8 argfile avoids Windows ANSI command-line loss, including Chinese paths.
        info.ArgumentList.Add("-@"); info.ArgumentList.Add("-");
        using var process = Process.Start(info) ?? throw new IOException("无法启动元数据工具。");
        using var bytes = new MemoryStream();
        var stdout = process.StandardOutput.BaseStream.CopyToAsync(bytes);
        var stderr = process.StandardError.ReadToEndAsync();
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        deadline.CancelAfter(timeout ?? TimeSpan.FromSeconds(30));
        try
        {
            foreach (var argument in argumentList)
            {
                await process.StandardInput.WriteLineAsync(argument.AsMemory(), deadline.Token);
            }
            process.StandardInput.Close();
            await process.WaitForExitAsync(deadline.Token);
        }
        catch
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync();
            await Task.WhenAll(stdout, stderr);
            if (deadline.IsCancellationRequested && !cancellation.IsCancellationRequested)
                throw new TimeoutException("元数据工具读取超时。");
            throw;
        }
        await stdout;
        var error = await stderr;
        if (process.ExitCode != 0) throw new IOException($"元数据工具失败（{process.ExitCode}）：{error.Trim()}");
        return bytes.ToArray();
    }

    public async Task<IReadOnlyDictionary<string, JsonElement>> ReadManyAsync(IReadOnlyList<string> files, CancellationToken cancellation = default)
    {
        if (files.Count is < 1 or > 64) throw new ArgumentException("批量读取限1至64个物理文件。");
        var paths = files.Select(Path.GetFullPath).ToArray(); var expected = paths.ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (expected.Count != paths.Length || paths.Any(path => !File.Exists(path))) throw new ArgumentException("批量文件重复或不存在。");
        var arguments = new[] { "-charset", "filename=UTF8", "-j", "-G1", "-a", "-s", "-n", "--" }.Concat(paths);
        var output = await RunAsync(arguments, cancellation);
        using var document = JsonDocument.Parse(output);
        if (document.RootElement.ValueKind != JsonValueKind.Array || document.RootElement.GetArrayLength() != paths.Length) throw new InvalidDataException("批量读取数量不一致。");
        var result = new Dictionary<string,JsonElement>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in document.RootElement.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object || !item.TryGetProperty("SourceFile", out var source) || source.ValueKind != JsonValueKind.String) throw new InvalidDataException("批量返回身份缺失。");
            var path = Path.GetFullPath(source.GetString()!);
            if (!expected.Contains(path) || !result.TryAdd(path, item.Clone())) throw new InvalidDataException("批量返回身份未知或重复。");
        }
        return result;
    }

    public async Task<JsonElement> ReadAsync(string file, CancellationToken cancellation = default)
    {
        if (!File.Exists(file)) throw new FileNotFoundException("照片不存在。", file);
        var output = await RunAsync(["-charset", "filename=UTF8", "-j", "-G1", "-a", "-s", "-n", "--", Path.GetFullPath(file)], cancellation);
        using var document = JsonDocument.Parse(output);
        if (document.RootElement.ValueKind != JsonValueKind.Array || document.RootElement.GetArrayLength() != 1)
            throw new InvalidDataException("元数据返回格式不正确。");
        var item = document.RootElement[0];
        if (item.ValueKind != JsonValueKind.Object || !item.TryGetProperty("SourceFile", out var source) || source.ValueKind != JsonValueKind.String ||
            !Path.GetFullPath(source.GetString()!).Equals(Path.GetFullPath(file), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("元数据返回文件身份不一致。");
        if (item.TryGetProperty("ExifTool:Error", out _) || item.TryGetProperty("Error", out _))
            throw new InvalidDataException("照片元数据读取失败。");
        return item.Clone();
    }
}
