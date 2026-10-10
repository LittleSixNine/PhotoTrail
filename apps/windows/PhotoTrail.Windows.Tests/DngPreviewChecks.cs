using System.Security.Cryptography;
using PhotoTrail.Windows;

static class DngPreviewChecks
{
    public static async Task RunAsync(ExifToolClient client, string fixtures, string root)
    {
        var folder = Path.Combine(root,"dng-preview-"+Guid.NewGuid().ToString("N")); Directory.CreateDirectory(folder);
        var source = Path.Combine(folder,"内嵌预览.DNG"); File.Copy(Path.Combine(fixtures,"sidecar.DNG"),source);
        var hash = await PhotoDocument.HashAsync(source);
        var count=0;
        void Check(bool value,string label){if(!value)throw new Exception(label);count++;Console.WriteLine("PASS "+label);}
        async Task Reject(Func<Task> action,string label)
        {
            try{await action();}catch(Exception e) when(e is IOException or InvalidDataException or NotSupportedException or OperationCanceledException){Check(true,label);return;}
            throw new Exception(label);
        }
        var prior = Directory.GetFiles(Path.GetTempPath(),"PhotoTrail-preview-*.jpg").Order().ToArray();
        var image=await Task.Run(()=>PhotoPreview.LoadDngAsync(client,source,hash,1));
        Check(image.IsFrozen && image.PixelWidth>0 && image.PixelHeight>0 && Math.Max(image.PixelWidth,image.PixelHeight)<=512,"DNG embedded JPEG decoded/frozen/bounded");
        var rotated=await Task.Run(()=>PhotoPreview.LoadDngAsync(client,source,hash,6));
        Check(rotated.PixelWidth==image.PixelHeight && rotated.PixelHeight==image.PixelWidth,"DNG preview applies source orientation");
        Check(await PhotoDocument.HashAsync(source)==hash,"DNG source bytes unchanged");
        using(var exclusive=File.Open(source,FileMode.Open,FileAccess.ReadWrite,FileShare.None))Check(exclusive.Length>0,"DNG preview releases source lock");
        await Reject(()=>PhotoPreview.LoadDngAsync(client,source,new string('0',64),1),"changed DNG baseline refused before extraction");
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        await Reject(()=>PhotoPreview.LoadDngAsync(client,source,hash,1,cancelled.Token),"cancelled DNG preview refused");
        var noPreview=Path.Combine(folder,"no-preview.jpg");File.Copy(Path.Combine(fixtures,"aligned.jpg"),noPreview);
        await Reject(()=>PhotoPreview.LoadDngAsync(client,noPreview,Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(noPreview))),1),"absent embedded preview gives clear refusal");
        var oversized=Path.Combine(folder,"oversized.DNG");using(var file=File.Create(oversized))file.SetLength(PhotoPreview.MaximumBytes+1);
        await Reject(()=>PhotoPreview.LoadDngAsync(client,oversized,"",1),"oversized DNG refused before extraction");
        Check(prior.SequenceEqual(Directory.GetFiles(Path.GetTempPath(),"PhotoTrail-preview-*.jpg").Order()),"temporary previews cleaned after success and refusal");
        var unicodeTemp=Path.Combine(folder,"临时 100%f");Directory.CreateDirectory(unicodeTemp);
        var oldTemp=Environment.GetEnvironmentVariable("TEMP");var oldTmp=Environment.GetEnvironmentVariable("TMP");
        try
        {
            Environment.SetEnvironmentVariable("TEMP",unicodeTemp);Environment.SetEnvironmentVariable("TMP",unicodeTemp);
            Check(Path.GetTempPath().TrimEnd(Path.DirectorySeparatorChar)==unicodeTemp,"isolated Unicode/percent temporary folder selected");
            var unicodeImage=await Task.Run(()=>PhotoPreview.LoadDngAsync(client,source,hash,1));
            Check(unicodeImage.IsFrozen && !Directory.EnumerateFileSystemEntries(unicodeTemp).Any(),"Unicode/percent output decoded and cleaned");
        }
        finally{Environment.SetEnvironmentVariable("TEMP",oldTemp);Environment.SetEnvironmentVariable("TMP",oldTmp);}
        Console.WriteLine($"DNG preview checks complete: {count}; evidence {folder}");
    }
}