using PhotoTrail.Windows;

static class ToolFailureChecks
{
    internal static async Task RunAsync()
    {
        string self = Environment.ProcessPath ?? throw new Exception("Missing test process");
        int passed = 0;
        async Task Refuses<T>(Func<Task> action, string name) where T : Exception
        {
            try { await action(); }
            catch (T) { Console.WriteLine("PASS " + name); passed++; return; }
            throw new Exception("Expected refusal: " + name);
        }
        await Refuses<ArgumentException>(async () => await new ExifToolClient("not-present.exe").RunAsync(["bad\nargument"]), "invalid tool argument before launch");
        await Refuses<IOException>(async () => await new ExifToolClient(self, "--fake-error").RunAsync([]), "injected tool nonzero exit");
        await Refuses<TimeoutException>(async () => await new ExifToolClient(self, "--fake-slow").RunAsync([], timeout: TimeSpan.FromMilliseconds(100)), "injected slow tool timeout and termination");
        using var cancel = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));
        await Refuses<OperationCanceledException>(async () => await new ExifToolClient(self, "--fake-slow").RunAsync([], cancel.Token), "controlled tool cancellation and termination");
        // A fresh missing path tests the real process-start diagnostic without changing any installed tool.
        try { await new ExifToolClient(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "ExifTool.exe")).RunAsync(["-ver"]); }
        catch (System.ComponentModel.Win32Exception) { Console.WriteLine("PASS actual missing executable process-start error"); passed++; }
        if (passed != 5) throw new Exception("Tool failure checks incomplete");
    }
}
