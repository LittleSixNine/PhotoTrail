using PhotoTrail.Windows;
static class SourceVersionChecks
{
 public static async Task RunAsync(ExifToolClient client,string fixtures,string output)
 {
  var folder=Path.Combine(output,"source-version-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);var source=Path.Combine(folder,"sample.jpg");File.Copy(Path.Combine(fixtures,"aligned.jpg"),source);
  var hash=await PhotoDocument.HashAsync(source);var photo=await PhotoDocument.LoadAsync(client,source);photo.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","version check"}});
  var count=0;void Check(bool value){if(!value)throw new Exception("Source version assertion failed");count++;}
  async Task Reject(Func<Task> action){try{await action();throw new Exception("Stale source accepted");}catch(IOException){count++;}}
  await photo.EnsureUnchangedAsync();Check(true);
  var sidecar=Path.ChangeExtension(source,".xmp");File.Copy(Path.Combine(fixtures,"sidecar.xmp"),sidecar);
  await Reject(()=>photo.EnsureUnchangedAsync());var target=Path.Combine(folder,"out");Directory.CreateDirectory(target);
  await Reject(async()=>{await MetadataCopy.SaveAsync(client,photo,target);});Check(Directory.GetFileSystemEntries(target).Length==0);Check(await PhotoDocument.HashAsync(source)==hash);
  var paired=await PhotoDocument.LoadAsync(client,source);await paired.EnsureUnchangedAsync();Check(paired.SidecarPath==sidecar);
  File.AppendAllText(sidecar," ");await Reject(()=>paired.EnsureUnchangedAsync());
  File.Copy(Path.Combine(fixtures,"sidecar.xmp"),sidecar,true);await paired.EnsureUnchangedAsync();Check(true);
  File.Move(sidecar,sidecar+".missing");await Reject(()=>paired.EnsureUnchangedAsync());await photo.EnsureUnchangedAsync();Check(true);
  var standalone=Path.Combine(folder,"standalone.xmp");File.Copy(sidecar+".missing",standalone);var xmp=await PhotoDocument.LoadAsync(client,standalone);await xmp.EnsureUnchangedAsync();Check(true);
  File.AppendAllText(source,"changed");await Reject(()=>photo.EnsureUnchangedAsync());
  Console.WriteLine($"{count} source/sidecar version assertions passed: {folder}");
 }
}
