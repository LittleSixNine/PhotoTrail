using PhotoTrail.Windows;

static class BatchChecks
{
    public static async Task RunAsync(ExifToolClient client,string fixtures,string output)
    {
        var count=0;void Check(bool ok,string label){if(!ok)throw new Exception(label);count++;Console.WriteLine("PASS "+label);}
        var folder=Path.Combine(output,"batch-read-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        var first=Path.Combine(folder,"中文 空格.jpg");var second=Path.Combine(folder,"second.jpg");var sidecar=Path.ChangeExtension(first,".xmp");
        File.Copy(Path.Combine(fixtures,"aligned.jpg"),first);File.Copy(Path.Combine(fixtures,"conflict.jpg"),second);File.Copy(Path.Combine(fixtures,"sidecar.xmp"),sidecar);
        var before=await PhotoDocument.HashAsync(first);var pairedBefore=await PhotoDocument.HashAsync(sidecar);
        var batch=await PhotoDocument.LoadBatchAsync(client,new[]{first,second,sidecar});
        Check(batch.Count==3 && batch.All(row=>row.Document is not null && row.Error is null),"batch reads Chinese path and shared paired XMP");
        foreach(var reading in batch)
        {
            var single=await PhotoDocument.LoadAsync(client,reading.FilePath);var photo=reading.Document!;
            Check(photo.SourceHash==single.SourceHash && photo.SidecarHash==single.SidecarHash && photo.FileType==single.FileType && PhotoDocument.EditableTags.All(tag=>photo.Value(tag)==single.Value(tag)),"batch metadata/source version agrees with single read");
        }
        var bad=Path.Combine(folder,"not-image.jpg");File.WriteAllText(bad,"plain text, no image");
        var missing=Path.Combine(folder,"missing-file.jpg");
        var mixed=await PhotoDocument.LoadBatchAsync(client,new[]{first,bad,missing,second});
        Check(mixed[0].Document is not null && mixed[3].Document is not null && mixed[1].Document is null && mixed[2].Document is null,"bad and missing files isolated from good neighbours");
        var corrupt=Path.Combine(folder,"corrupt.jpg");File.WriteAllBytes(corrupt,new byte[]{0xff,0xd8,0xff,0xe1,0,20,1,2});
        var isolated=await PhotoDocument.LoadBatchAsync(client,new[]{first,corrupt,second});
        Check(isolated[0].Document is not null && isolated[1].Document is null && isolated[2].Document is not null,"native truncated JPEG warning refused without dropping neighbours");
        var empty=Path.Combine(folder,"empty.jpg");File.WriteAllBytes(empty,Array.Empty<byte>());
        try{await client.ReadManyAsync(new[]{first,empty,second});throw new Exception("native empty-file command did not fail");}catch(IOException){Check(true,"native empty JPEG makes batch tool command fail");}
        var recovered=await PhotoDocument.LoadBatchAsync(client,new[]{first,empty,second});
        Check(recovered[0].Document is not null && recovered[1].Document is null && recovered[2].Document is not null,"native command failure falls back per file without losing good neighbours");
        Check(mixed.Select(row=>row.FilePath).SequenceEqual(new[]{first,bad,missing,second}),"input order retained with failures");
        var disguised=Path.Combine(folder,"fake-sidecar.jpg");File.Copy(Path.Combine(fixtures,"aligned.jpg"),disguised);File.Copy(Path.Combine(fixtures,"aligned.jpg"),Path.ChangeExtension(disguised,".xmp"));
        Check((await PhotoDocument.LoadBatchAsync(client,new[]{disguised}))[0].Document is null,"image disguised as XMP sidecar refused");
        try{await PhotoDocument.LoadBatchAsync(client,new[]{first,first});throw new Exception("duplicate accepted");}catch(ArgumentException){Check(true,"duplicate batch targets refused");}
        try{await PhotoDocument.LoadBatchAsync(client,Enumerable.Repeat(first,33).ToArray());throw new Exception("limit accepted");}catch(ArgumentException){Check(true,"batch upper bound refused before IO");}
        using(var cancellation=new CancellationTokenSource())
        {cancellation.Cancel();try{await PhotoDocument.LoadBatchAsync(client,new[]{first},cancellation.Token);throw new Exception("cancel accepted");}catch(OperationCanceledException){Check(true,"cancelled batch reported");}}
        var self=Environment.ProcessPath!;
        var reversed=await new ExifToolClient(self,"--fake-batch-reversed").ReadManyAsync(new[]{first,second});
        Check(reversed[first].GetProperty("XMP-dc:Title").ToString()==Path.GetFileName(first) && reversed[second].GetProperty("XMP-dc:Title").ToString()==Path.GetFileName(second),"reply order cannot mix file identities");
        foreach(var mode in new[]{"--fake-batch-unknown","--fake-batch-duplicate","--fake-batch-missing"})
        {try{await new ExifToolClient(self,mode).ReadManyAsync(new[]{first,second});throw new Exception("bad identity accepted");}catch(InvalidDataException){Check(true,"unknown duplicate or missing response refused");}}
        try{await new ExifToolClient(self,"--fake-batch-unknown").ReadAsync(first);throw new Exception("bad single identity accepted");}catch(InvalidDataException){Check(true,"fallback single read also verifies exact source identity");}
        foreach(var mode in new[]{"--fake-batch-modified","--fake-batch-sidecar"})
        {
            var file=Path.Combine(folder,mode+".jpg");File.Copy(Path.Combine(fixtures,"aligned.jpg"),file);
            var result=await PhotoDocument.LoadBatchAsync(new ExifToolClient(self,mode),new[]{file});
            Check(result[0].Document is null && result[0].Error!.Contains("改变"),"changed source or late sidecar rejected after batch read");
        }
        Check(await PhotoDocument.HashAsync(first)==before && await PhotoDocument.HashAsync(sidecar)==pairedBefore,"valid sources and sidecar remain unchanged");
        Console.WriteLine($"Batch checks complete: {count}; evidence {folder}");
    }
}
