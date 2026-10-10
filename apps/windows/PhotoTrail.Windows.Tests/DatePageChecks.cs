using PhotoTrail.Windows;
using System.Text;
static class DatePageChecks
{
    public static async Task RunAsync(ExifToolClient client,string output)
    {
        string folder=Path.Combine(output,"date-page-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        var documents=new List<PhotoDocument>();int passed=0;
        void Check(bool ok,string label){if(!ok)throw new Exception(label);passed++;Console.WriteLine("PASS "+label);}
        async Task Reject(Func<Task> action,string label){try{await action();}catch(Exception e)when(e is ArgumentException or InvalidOperationException or DateFailure){Check(true,label);return;}throw new Exception(label);}
        string[] suffixes=[".123456789Z",".1+00:00",".123-00:00",""];
        for(int i=0;i<4;i++){
            string file=Path.Combine(folder,$"20240229_123456-{i}.xmp");
            await File.WriteAllTextAsync(file,"<x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description rdf:about='' xmlns:exif='http://ns.adobe.com/exif/1.0/' exif:DateTimeOriginal='2024-02-29T12:34:56"+suffixes[i]+"'/></rdf:RDF></x:xmpmeta>",new UTF8Encoding(false));
            documents.Add(await PhotoDocument.LoadAsync(client,file));
        }
        async Task<DatePagePreview> Plan(DatePageOptions option)=>await DatePagePreview.CreateAsync(documents,option,1,()=>1,CancellationToken.None);
        foreach(var option in new[]{new DatePageOptions(0,Days:1),new DatePageOptions(1,Seconds:1,Start:"2024:01:01 00:00:00.123456789Z"),
            new DatePageOptions(2,Components:new(){["year"]=2025,["day"]=28}),new DatePageOptions(3,Start:"2024:01:01 00:00:00Z",End:"2024:01:01 00:00:05Z"),
            new DatePageOptions(4,Pattern:"([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})",Template:"$1:$2:$3 15:$5:$6")}) {
            var preview=await Plan(option);Check(documents.All(d=>d.Draft.Count==0),"preview-no-draft-"+option.Mode);
            preview.Apply();Check(documents.Select(d=>d.Value(DatePagePreview.Field)).SequenceEqual(preview.Values),"apply-"+option.Mode);
            string copies=Path.Combine(folder,"mode-"+option.Mode);Directory.CreateDirectory(copies);
            foreach(var doc in documents){var copy=await MetadataCopy.SaveAsync(client,doc,copies);var read=await PhotoDocument.LoadAsync(client,copy);
                Check(read.Value(DatePagePreview.Field)==doc.Value(DatePagePreview.Field),"copy-read-"+option.Mode);Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash,"source-protected-"+option.Mode);doc.ClearDraft();}
            await Reject(()=>{preview.Apply();return Task.CompletedTask;},"consumed-"+option.Mode);
        }
        await Reject(()=>Plan(new(2,Components:new(){["year"]=2025})),"single-leap-invalid-no-draft");
        await Reject(()=>Plan(new(1,Start:"1582:10:10 00:00:00",Seconds:1)),"cutover-gap-no-draft");
        await Reject(()=>Plan(new(1,Start:"2024:01:01 00:00:00\n",Seconds:1)),"LF-rejected-no-draft");
        var stale=await Plan(new(0,Seconds:1));documents[^1].SetDraft(new Dictionary<string,string>{["XMP-dc:Title"]="other entry"});
        await Reject(()=>{stale.Apply();return Task.CompletedTask;},"whole-batch-stale-before-any-write");Check(documents.Take(3).All(d=>d.Draft.Count==0),"no-partial-stale-draft");documents[^1].ClearDraft();
        var history=await Plan(new(1,Start:"1500:02:29 00:00:00",Seconds:1));history.Apply();Check(documents[0].Value(DatePagePreview.Field)=="1500:02:29 00:00:00","candidate-historical-draft");
        try{PhotoDocument.ValidateChanges(new Dictionary<string,string>{[DatePagePreview.Field]="1500:02:29 00:00:00"});throw new Exception("old path changed");}catch(ArgumentException){Check(true,"manual-remains-old-calendar");}
        string historical=Path.Combine(folder,"historical");Directory.CreateDirectory(historical);var saved=await MetadataCopy.SaveAsync(client,documents[0],historical);
        Check((await PhotoDocument.LoadAsync(client,saved)).Value(DatePagePreview.Field)=="1500:02:29 00:00:00","historical-copy-no-old-revalidation");
        foreach(var doc in documents){Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash,"final-source-hash");doc.ClearDraft();}
        Console.WriteLine($"Date page checks complete: {passed}; evidence {folder}");
    }
}
