using System.Security.Cryptography;
using PhotoTrail.Windows;

if (args.FirstOrDefault()?.StartsWith("--fake-") == true)
{
    Console.InputEncoding = new System.Text.UTF8Encoding(false);
    Console.OutputEncoding = new System.Text.UTF8Encoding(false);
    var fakeInput = await Console.In.ReadToEndAsync();
    switch (args[0])
    {
        case "--fake-batch-reversed":
        case "--fake-batch-unknown":
        case "--fake-batch-duplicate":
        case "--fake-batch-missing":
        case "--fake-batch-modified":
        case "--fake-batch-sidecar":
            var fakePaths = fakeInput.Split('\n').Select(line=>line.TrimEnd('\r')).SkipWhile(line=>line!="--").Skip(1).Where(line=>line.Length>0).ToArray();
            if(args[0]=="--fake-batch-modified")File.AppendAllText(fakePaths[0],"modified during read");
            if(args[0]=="--fake-batch-sidecar")File.WriteAllText(Path.ChangeExtension(fakePaths[0],".xmp"),"sidecar appeared during read");
            var responses=fakePaths.Reverse().ToArray();
            if(args[0]=="--fake-batch-unknown")responses[0]=Path.Combine(Path.GetDirectoryName(responses[0])!,"not-requested.jpg");
            if(args[0]=="--fake-batch-duplicate")responses=Enumerable.Repeat(fakePaths[0],fakePaths.Length).ToArray();
            if(args[0]=="--fake-batch-missing")responses=responses.Take(Math.Max(0,responses.Length-1)).ToArray();
            Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(responses.Select(file=>new Dictionary<string,string>{["SourceFile"]=file,["File:FileType"]="JPEG",["File:MIMEType"]="image/jpeg",["XMP-dc:Title"]=Path.GetFileName(file)})));return;
        case "--fake-invalid": Console.WriteLine("invalid json"); return;
        case "--fake-error": Console.Error.WriteLine("simulated process failure"); Environment.Exit(7); return;
        case "--fake-slow": await Task.Delay(10_000); Console.WriteLine("[]"); return;
    }
}
static void Check(bool value, string message) { if (!value) throw new Exception(message); Console.WriteLine("PASS " + message); }
if (args.FirstOrDefault() == "--theme-checks") { ThemeChecks.Run(); return; }
if (args.FirstOrDefault() == "--preview-checks") { await PreviewChecks.RunAsync(); return; }
if (args.FirstOrDefault() == "--history-remember") { try { foreach (var path in args.Skip(2)) TrackHistory.RememberAndSave(args[1],path); } catch (Exception error) { Console.Error.WriteLine(error); Environment.ExitCode = 1; } return; }
if (args.FirstOrDefault() == "--history-checks") { try { TrackHistoryChecks.Run(); } catch (Exception error) { Console.Error.WriteLine(error); Environment.ExitCode = 1; } return; }
if (args.FirstOrDefault() == "--clipboard-checks") { try { ClipboardChecks.Run(); } catch (Exception error) { Console.Error.WriteLine(error); Environment.ExitCode = 1; } return; }
if (args.FirstOrDefault() == "--preset-checks") { PresetChecks.Run(); return; }
if (args.FirstOrDefault() == "--date-checks") { DateChecks.Run(); return; }
if (args.FirstOrDefault() == "--csv-checks") { CsvChecks.Run(); return; }
if (args.FirstOrDefault() == "--rename-bulk-checks") { await RenameBulkChecks.RunAsync(); return; }
if (args.FirstOrDefault() == "--rename-execution-checks") { await RenameExecutionChecks.RunAsync(); return; }
if (args.FirstOrDefault() == "--rename-preset-checks") { RenamePresetChecks.Run(); return; }
if (args.FirstOrDefault() == "--rename-checks") { await RenameChecks.RunAsync(); return; }
if (args.FirstOrDefault() == "--google-checks") { GoogleChecks.Run(); return; }
if (args.FirstOrDefault() == "--key-checks") { KeyChecks.Run(); return; }
if (args.FirstOrDefault() == "--track-checks") { TrackChecks.Run(); return; }
if (args.FirstOrDefault() == "--kml-checks") { KmlChecks.Run(); return; }
var point = "{\"type\":\"point\",\"longitude\":135.7681,\"latitude\":35.0116}";
Check(MapMessage.TryPoint(MapMessage.Page, point, out var parsed) && parsed!.Latitude == 35.0116, "valid WGS84 point");
Check(!MapMessage.TryPoint("https://unexpected.example/", point, out _), "foreign origin rejected");
foreach (var invalid in new[] { "{}", "{", "[]", point.Replace("135.7681", "181"), point.Replace("35.0116", "91"), point.Replace("135.7681", "\"bad\"") })
    Check(!MapMessage.TryPoint(MapMessage.Page, invalid, out _), "invalid message rejected");
foreach (var type in new[] { "ready", "map-error" })
{
    var message = "{\"type\":\"" + type + "\"}";
    Func<string, string, bool> accept = type == "ready" ? MapMessage.IsReady : MapMessage.IsError;
    Check(accept(MapMessage.Page, message), type + " from local page accepted");
    Check(!accept("https://unexpected.example/", message), type + " foreign origin rejected");
    foreach (var invalid in new[] { "{}", "{", "[]", "{\"type\":1}", point, message + new string(' ', 4096) })
        Check(!accept(MapMessage.Page, invalid), type + " invalid/oversized message rejected");
}
Check(!MapMessage.IsError(MapMessage.Page, "{\"type\":\"ready\"}") && !MapMessage.IsReady(MapMessage.Page, "{\"type\":\"map-error\"}"), "ready and error remain distinct");
if (args.FirstOrDefault() == "--map-checks") return;
var tool = Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL");
var script = Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL_SCRIPT");
var fixtures = Environment.GetEnvironmentVariable("PHOTOTRAIL_FIXTURES");
if (string.IsNullOrEmpty(tool) || string.IsNullOrEmpty(fixtures)) throw new Exception("Set PHOTOTRAIL_EXIFTOOL and PHOTOTRAIL_FIXTURES for real tool validation.");
var client = new ExifToolClient(tool, script);
if (args.FirstOrDefault() == "--gps-clipboard-copy-checks") { try { await ClipboardChecks.RunGpsCopyAsync(client,fixtures,Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output")); } catch (Exception error) { Console.Error.WriteLine(error); Environment.ExitCode = 1; } return; }
if (args.FirstOrDefault() == "--dng-preview-checks") { try { await DngPreviewChecks.RunAsync(client,fixtures,Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output")); } catch (Exception error) { Console.Error.WriteLine(error); Environment.ExitCode = 1; } return; }
if (args.FirstOrDefault() == "--source-version-checks") { await SourceVersionChecks.RunAsync(client, fixtures, Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output")); return; }
if (args.FirstOrDefault() == "--xmp-checks") { await XmpChecks.RunAsync(client, fixtures, Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output")); return; }
if (args.FirstOrDefault() == "--common-fields-checks") { try { await CommonFieldsChecks.RunAsync(client, fixtures, Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output")); } catch (Exception error) { Console.Error.WriteLine(error); Environment.ExitCode = 1; } return; }
if (args.FirstOrDefault() == "--batch-checks") { await BatchChecks.RunAsync(client, fixtures, Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output")); return; }
if (args.FirstOrDefault() == "--preset-copy-checks") { await PresetChecks.RunCopyAsync(client, fixtures, Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output")); return; }
if (args.FirstOrDefault() == "--date-copy-checks") { await DateChecks.RunCopyAsync(client, fixtures, Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output")); return; }
if (args.FirstOrDefault() == "--csv-copy-checks") { await CsvChecks.RunCopyAsync(client, fixtures, Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output")); return; }
if (args.FirstOrDefault() == "--region-checks") { await RegionChecks.RunAsync(client, fixtures, Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output")); return; }
if (args.FirstOrDefault() == "--readonly-output")
{
    var folder = args.ElementAtOrDefault(1) ?? throw new ArgumentException("Provide an existing denied-write test folder");
    var document = await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"aligned.jpg"));
    document.SetDraft(new Dictionary<string,string>{["XMP-dc:Title"]="denied output validation"});
    try { await MetadataCopy.SaveAsync(client,document,folder); throw new Exception("Unwritable output accepted"); }
    catch (UnauthorizedAccessException) { Console.WriteLine("PASS unwritable directory refuses copy creation"); }
    Check(!Directory.EnumerateFileSystemEntries(folder).Any(),"unwritable directory contains no partial output");
    Check(document.Draft.Count==1,"unwritable output preserves draft");
    Check(await PhotoDocument.HashAsync(document.FilePath)==document.SourceHash,"unwritable output leaves original unchanged");
    return;
}
if (args.FirstOrDefault() is "--benchmark" or "--batch-benchmark")
{
    var count = int.Parse(args.ElementAtOrDefault(1) ?? "300");
    if (count is < 1 or > 3000) throw new ArgumentException("Benchmark count must be 1..3000");
    var evidenceRoot = Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing private evidence output");
    var folder = Path.Combine(evidenceRoot, "import-benchmark-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(folder);
    for (var index = 0; index < count; index++) File.Copy(Path.Combine(fixtures,"aligned.jpg"), Path.Combine(folder,$"照片 {index:0000}.jpg"));
    var clock = System.Diagnostics.Stopwatch.StartNew();
    var documents = new List<PhotoDocument>();
    long peak = 0;
    var inputs = Directory.GetFiles(folder);
    if (args[0] == "--batch-benchmark")
        foreach (var batch in inputs.Chunk(32))
        {
            var readings = await PhotoDocument.LoadBatchAsync(client, batch);
            if (readings.Any(row => row.Document is null)) throw new Exception("Benchmark read failure");
            documents.AddRange(readings.Select(row => row.Document!));
            using var process = System.Diagnostics.Process.GetCurrentProcess(); peak = Math.Max(peak,process.WorkingSet64);
            Console.WriteLine($"Imported {documents.Count}/{count}");
        }
    else foreach (var path in inputs)
    {
        documents.Add(await PhotoDocument.LoadAsync(client,path));
        using var process = System.Diagnostics.Process.GetCurrentProcess();
        peak = Math.Max(peak,process.WorkingSet64);
        if (documents.Count % 50 == 0) Console.WriteLine($"Imported {documents.Count}/{count}");
    }
    clock.Stop();
    var expectedHash = await PhotoDocument.HashAsync(Path.Combine(fixtures,"aligned.jpg"));
    Check(documents.Count == count && documents.All(photo => photo.SourceHash == expectedHash && photo.Value("XMP-dc:Creator") == "Marco S Hyman"), "benchmark file versions and authors verified");
    using var measuredProcess = System.Diagnostics.Process.GetCurrentProcess();
    Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new { count,elapsedSeconds=clock.Elapsed.TotalSeconds,photosPerSecond=count/clock.Elapsed.TotalSeconds,sampledPeakWorkingSetBytes=peak,processLifetimePeakWorkingSetBytes=measuredProcess.PeakWorkingSet64,mode=args[0],scope="console metadata loader; excludes WPF/WebView2/thumbnail and ExifTool child memory",folder }));
    return;
}
{
    var rejectionRoot = Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing private evidence output");
    var disguised = Path.Combine(rejectionRoot,"not-a-photo-" + Guid.NewGuid().ToString("N") + ".jpg");
    File.WriteAllText(disguised,"This is plain text, not image data.");
    try { await PhotoDocument.LoadAsync(client,disguised); throw new Exception("Disguised non-image accepted"); }
    catch (InvalidDataException) { Console.WriteLine("PASS non-image content refused despite image extension"); }
}
foreach (var (name, creator) in new[] { ("aligned.jpg", "Marco S Hyman"), ("conflict.jpg", "Alice XMP") })
{
    var file = Path.Combine(fixtures, name);
    var before = SHA256.HashData(File.ReadAllBytes(file));
    var metadata = await client.ReadAsync(file);
    Check(metadata.GetProperty("XMP-dc:Creator").ToString().Contains(creator), name + " expected author");
    Check(before.SequenceEqual(SHA256.HashData(File.ReadAllBytes(file))), name + " unchanged");
}
var missing = await client.ReadAsync(Path.Combine(fixtures, "missing.jpg"));
Check(!missing.TryGetProperty("XMP-dc:Creator", out _), "missing author stays missing");
using var cancel = new CancellationTokenSource();
cancel.Cancel();
try { await client.RunAsync(["-ver"], cancel.Token); throw new Exception("Cancelled call succeeded"); }
catch (OperationCanceledException) { Console.WriteLine("PASS cancellation reported"); }
{
    var self = Environment.ProcessPath ?? throw new Exception("Test process path unavailable");
    try { await new ExifToolClient("does-not-exist.exe").RunAsync(["bad\nargument"]); throw new Exception("Invalid argument accepted"); }
    catch (ArgumentException) { Console.WriteLine("PASS invalid argument refused before process start"); }
    try { await new ExifToolClient(self, "--fake-slow").RunAsync([], timeout: TimeSpan.FromMilliseconds(100)); throw new Exception("Timeout not reported"); }
    catch (TimeoutException) { Console.WriteLine("PASS timeout kills tool process"); }
    try { await new ExifToolClient(self, "--fake-error").RunAsync([]); throw new Exception("Process failure not reported"); }
    catch (IOException) { Console.WriteLine("PASS process failure reported"); }
    try { await new ExifToolClient(self, "--fake-invalid").ReadAsync(Path.Combine(fixtures, "aligned.jpg")); throw new Exception("Malformed JSON accepted"); }
    catch (System.Text.Json.JsonException) { Console.WriteLine("PASS malformed tool JSON rejected"); }
}
Console.WriteLine("Bootstrap checks complete.");
var evidence = Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Set PHOTOTRAIL_TEST_OUTPUT to a private test directory.");
var testRoot = Path.Combine(evidence, "metadata-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(testRoot);
var inputRoot = Path.Combine(testRoot, "中文 样本"); Directory.CreateDirectory(inputRoot);
var outputRoot = Path.Combine(testRoot, "保存 副本"); Directory.CreateDirectory(outputRoot);
var inputFile = Path.Combine(inputRoot, "照片 中文.jpg"); File.Copy(Path.Combine(fixtures, "aligned.jpg"), inputFile);
await client.RunAsync(["-charset","filename=UTF8","-overwrite_original","-XMP-dc:Title-fr=Bonjour","-XMP-dc:Description-de=Beschreibung","--",inputFile]);
var photo = await PhotoDocument.LoadAsync(client, inputFile);
var changes = new Dictionary<string,string> { ["XMP-dc:Creator"]="作者 六九",["XMP-dc:Title"]="测试 标题",["XMP-dc:Description"]="中文描述\n第二行 $HOME @test \"引号\" \\literal",["XMP-dc:Subject"]="京都\n旅行, 夜景",["XMP-exif:DateTimeOriginal"]="2024:02:29 12:34:56+09:00" };
photo.SetDraft(changes);
var saved = await MetadataCopy.SaveAsync(client, photo, outputRoot);
Check(File.Exists(saved), "JPEG copy saved with five fields");
Check(await PhotoDocument.HashAsync(inputFile)==photo.SourceHash, "original JPEG unchanged after save");
Check(await MetadataCopy.JpegPixelsAsync(inputFile)==await MetadataCopy.JpegPixelsAsync(saved), "JPEG pixel payload unchanged");
Check(photo.Draft.Count==5, "source draft retained after saving a separate copy");
var savedMetadata=await client.ReadAsync(saved);
Check(savedMetadata.GetProperty("XMP-dc:Title-fr").ToString()=="Bonjour" && savedMetadata.GetProperty("XMP-dc:Description-de").ToString()=="Beschreibung", "alternate language values preserved");
try { await MetadataCopy.SaveAsync(client,photo,outputRoot); throw new Exception("Existing output overwritten"); } catch(IOException) { Console.WriteLine("PASS existing target refused"); }
try { photo.SetDraft(new Dictionary<string,string>{["XMP-exif:DateTimeOriginal"]="2024:02:30 12:00:00"}); throw new Exception("Invalid date accepted"); } catch(ArgumentException) { Console.WriteLine("PASS invalid calendar date refused"); }
photo.ClearDraft(); Check(photo.Value("XMP-dc:Creator")=="Marco S Hyman", "undo restores source value");
try { photo.SetDraft(new Dictionary<string,string>{["XMP-dc:Title"]="must not apply",["File:FileName"]="unapproved.jpg"}); throw new Exception("Unknown field accepted"); } catch(ArgumentException) { Console.WriteLine("PASS unknown field refused"); }
Check(photo.Draft.Count==0,"invalid draft application is atomic");
var dng=await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"sidecar.DNG"));
Check(dng.Value("XMP-dc:Creator")=="Sidecar Alice", "sidecar author wins over embedded XMP");
dng.SetDraft(new Dictionary<string,string>{["XMP-dc:Creator"]="旁车 作者"});
var pairedRoot=Path.Combine(testRoot,"旁车输出");Directory.CreateDirectory(pairedRoot);
var paired=await MetadataCopy.SaveAsync(client,dng,pairedRoot);
Check(await PhotoDocument.HashAsync(paired)==dng.SourceHash, "DNG copy remains byte identical");
var sidecarResult=await client.ReadAsync(Path.ChangeExtension(paired,".xmp"));
Check(PhotoDocument.Text(sidecarResult.GetProperty("XMP-dc:Creator"))=="旁车 作者", "paired XMP independently read back");
var changed=await PhotoDocument.LoadAsync(client,inputFile);
changed.SetDraft(new Dictionary<string,string>{["XMP-dc:Title"]="Changed"});
await File.AppendAllTextAsync(inputFile,"changed by external test");
var refusedRoot=Path.Combine(testRoot,"冲突输出");Directory.CreateDirectory(refusedRoot);
try { await MetadataCopy.SaveAsync(client,changed,refusedRoot); throw new Exception("External modification ignored"); } catch(IOException) { Console.WriteLine("PASS external modification refused"); }
Check(!Directory.EnumerateFileSystemEntries(refusedRoot).Any(), "failed save leaves no delivered output");
var failurePhoto=await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"aligned.jpg"));
failurePhoto.SetDraft(new Dictionary<string,string>{["XMP-dc:Title"]="failure test"});
var failureRoot=Path.Combine(testRoot,"工具失败");Directory.CreateDirectory(failureRoot);
try { await MetadataCopy.SaveAsync(new ExifToolClient(Environment.ProcessPath!,"--fake-error"),failurePhoto,failureRoot); throw new Exception("Failed writer accepted"); } catch(IOException) { Console.WriteLine("PASS writer failure reported"); }
Check(!Directory.EnumerateFileSystemEntries(failureRoot).Any() && failurePhoto.Draft.Count==1,"failed writer preserves draft and delivers nothing");
var cancelRoot=Path.Combine(testRoot,"取消输出");Directory.CreateDirectory(cancelRoot);
using var saveCancel=new CancellationTokenSource(TimeSpan.FromMilliseconds(150));
try { await MetadataCopy.SaveAsync(new ExifToolClient(Environment.ProcessPath!,"--fake-slow"),failurePhoto,cancelRoot,saveCancel.Token); throw new Exception("Cancelled save accepted"); } catch(OperationCanceledException) { Console.WriteLine("PASS cancelled writer terminated"); }
Check(!Directory.EnumerateFileSystemEntries(cancelRoot).Any() && await PhotoDocument.HashAsync(failurePhoto.FilePath)==failurePhoto.SourceHash,"cancelled save leaves original unchanged and no output");
Console.WriteLine("Metadata copy checks complete. Private evidence: " + testRoot);
await GpsChecks.RunAsync(client,fixtures,evidence);
