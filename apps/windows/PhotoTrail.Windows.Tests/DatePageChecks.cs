using PhotoTrail.Windows;
using System.Text;
static class DatePageChecks
{
    public static async Task RunOffsetAsync(ExifToolClient client,string output)
    {
        string folder=Path.Combine(output,"offset-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        int passed=0;
        void Check(bool ok,string label){if(!ok)throw new Exception(label);passed++;Console.WriteLine("PASS "+label);}
        async Task Reject(Func<Task> action,string label){try{await action();}catch(Exception e)when(e is ArgumentException or InvalidOperationException or DateFailure or IOException or OperationCanceledException or System.ComponentModel.Win32Exception){Check(true,label);return;}throw new Exception(label);}
        async Task<PhotoDocument> Load(string name,string? date){
            string file=Path.Combine(folder,name+".xmp");
            await File.WriteAllTextAsync(file,"<x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description rdf:about='' xmlns:exif='http://ns.adobe.com/exif/1.0/'"+(date is null?"":" exif:DateTimeOriginal='"+date+"'")+"/></rdf:RDF></x:xmpmeta>",new UTF8Encoding(false));
            return await PhotoDocument.LoadAsync(client,file);
        }
        var first=await Load("first","2024-02-29T12:34:56.123456789-00:00");
        var missing=await Load("middle",null);var last=await Load("last","2024-02-29T12:34:56.1+08:00");
        PhotoDocument[] docs=[last,missing,first];
        Task<DatePagePreview> Plan(IReadOnlyList<PhotoDocument> selection,DatePageOptions? options=null,CancellationToken token=default)=>DatePagePreview.CreateAsync(selection,options??new(0,Minutes:4,Seconds:15),1,()=>1,token);
        missing.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","keep title"}});
        var preview=await Plan(docs);
        Check(preview.Values.SequenceEqual(new string?[]{"2024:02:29 12:39:11.1+08:00",null,"2024:02:29 12:39:11.123456789-00:00"}),"mixed-middle-missing-order-precision-offset");
        Check(docs.All(d=>!d.Draft.ContainsKey(DatePagePreview.Field)),"preview-no-date-draft");preview.Apply();
        Check(missing.Draft.Count==1&&missing.Draft["XMP-dc:Title"]=="keep title","skip-preserves-other-draft");
        string copies=Path.Combine(folder,"copies");Directory.CreateDirectory(copies);
        foreach(var doc in docs){var copy=await MetadataCopy.SaveAsync(client,doc,copies);var read=await PhotoDocument.LoadAsync(client,copy);Check(read.Value(DatePagePreview.Field)==doc.Value(DatePagePreview.Field),"copy-date-read-"+Path.GetFileName(doc.FilePath));Check(read.Value("XMP-dc:Title")==doc.Value("XMP-dc:Title"),"copy-other-draft-read-"+Path.GetFileName(doc.FilePath));Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash,"source-hash-"+Path.GetFileName(doc.FilePath));doc.ClearDraft();}
        var allMissing=await Plan(new[]{missing});Check(allMissing.Values.All(v=>v is null),"all-missing-no-changes");allMissing.Apply();Check(missing.Draft.Count==0,"all-missing-no-draft");
        first.SetDraft(new Dictionary<string,string>{{DatePagePreview.Field,"2026:01:02 03:04:05.123Z"}});
        Check((await Plan(new[]{first})).Values[0]=="2026:01:02 03:08:20.123Z","existing-date-draft-priority");first.ClearDraft();
        first.SetDraft(new Dictionary<string,string>{{DatePagePreview.Field,"2026:01:02 03:04:05.123Z"}});
        Check((await Plan(new[]{first},new(0,Years:1,Months:1,Days:1,Hours:1,Minutes:1,Seconds:1))).Values[0]=="2027:02:03 04:05:06.123Z","all-six-components-order");first.ClearDraft();
        await Reject(()=>Plan(new[]{first},new(0,Years:1)),"invalid-leap-offset-rejected");
        await Reject(()=>Plan(new[]{missing},new(2,Components:new(){["year"]=2025})),"replace-missing-still-rejected");
        first.SetDraft(new Dictionary<string,string>{{DatePagePreview.Field,""},{"XMP-dc:Title","keep clear"}});
        var cleared=await Plan(new[]{first});Check(cleared.Values[0] is null,"cleared-date-draft-is-missing");cleared.Apply();Check(first.Draft[DatePagePreview.Field]==""&&first.Draft["XMP-dc:Title"]=="keep clear","skip-keeps-clear-and-other-draft");first.ClearDraft();
        var invalid=await Load("invalid","not-a-date");await Reject(()=>Plan(new[]{missing,invalid}),"invalid-date-not-skipped");
        var ctor=typeof(PhotoDocument).GetConstructors(System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance).Single();
        foreach(string raw in new[]{"[\"2024:02:29 12:34:56\"]","null","42","{}","\"\""}){
            var metadata=System.Text.Json.JsonSerializer.SerializeToElement(new Dictionary<string,object>{{"File:FileType","XMP"},{DatePagePreview.Field,System.Text.Json.JsonDocument.Parse(raw).RootElement.Clone()}});
            var wrong=(PhotoDocument)ctor.Invoke([missing.FilePath,null,metadata,null,missing.SourceHash,null]);
            await Reject(()=>Plan(new[]{wrong}),"wrong-type-or-empty-"+raw);
        }
        await Reject(()=>Plan(new[]{missing},new(0,Years:10000)),"all-missing-invalid-option-rejected");
        var revision=1;await Reject(()=>DatePagePreview.CreateAsync(docs,new(0,Seconds:1),1,()=>++revision,CancellationToken.None),"revision-invalidated");
        using(var cancel=new CancellationTokenSource()){cancel.Cancel();await Reject(()=>Plan(docs,token:cancel.Token),"canceled-no-partial-draft");}
        var stale=await Plan(docs);missing.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","changed after preview"}});await Reject(()=>{stale.Apply();return Task.CompletedTask;},"missing-draft-change-whole-batch-rejected");Check(first.Draft.Count==0&&last.Draft.Count==0,"stale-no-partial-draft");missing.ClearDraft();
        var original=await File.ReadAllBytesAsync(missing.FilePath);await File.AppendAllTextAsync(missing.FilePath," ");await Reject(()=>Plan(docs),"missing-source-change-rejected");await File.WriteAllBytesAsync(missing.FilePath,original);
        string lost=Path.Combine(folder,"lost.xmp");File.Move(missing.FilePath,lost);try{await Reject(()=>Plan(docs),"missing-source-read-failure-rejected");}finally{File.Move(lost,missing.FilePath);}
        await Reject(async()=>{await PhotoDocument.LoadAsync(new ExifToolClient("missing-exiftool.exe"),missing.FilePath);},"metadata-read-failure-not-missing");
        Check(docs.All(d=>d.Draft.Count==0),"final-no-drafts");foreach(var doc in docs)Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash,"final-source-"+Path.GetFileName(doc.FilePath));
        Console.WriteLine($"Offset skip checks complete: {passed}; evidence {folder}");
    }
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
