using PhotoTrail.Windows;
static class RegionChecks
{
 public static async Task RunAsync(ExifToolClient client,string fixtures,string output)
 {
  var count=0; void Check(bool value){if(!value)throw new Exception("Region save assertion failed");count++;}
  var folder=Path.Combine(output,"regions-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
  var photo=await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"aligned.jpg"));
  var fields=new Dictionary<string,string>{{"XMP-photoshop:Country","日本"},{"XMP-photoshop:State","京都府"},{"XMP-photoshop:City","京都市"},{"XMP-iptcCore:Location","左京区"},{"XMP-iptcCore:CountryCode","JPN"}};
  photo.SetDraft(fields);Check(photo.Draft.Count==5);
  foreach(var invalid in new[]{new Dictionary<string,string>{{"XMP-photoshop:City","changed"},{"XMP-iptcCore:CountryCode","JP"}},new Dictionary<string,string>{{"XMP-photoshop:City","x\ny"}},new Dictionary<string,string>{{"XMP-photoshop:City",new string('x',257)}}})
  {
   try {photo.SetDraft(invalid);throw new Exception("Invalid region accepted");}catch(ArgumentException){Check(photo.Value("XMP-photoshop:City")=="京都市");}
  }
  var saved=await MetadataCopy.SaveAsync(client,photo,folder);var metadata=await client.ReadAsync(saved);
  foreach(var field in fields)Check(metadata.GetProperty(field.Key).ToString()==field.Value);
  Check(await PhotoDocument.HashAsync(photo.FilePath)==photo.SourceHash);
  Check(await MetadataCopy.JpegPixelsAsync(saved)==await MetadataCopy.JpegPixelsAsync(photo.FilePath));
  var reopened=await PhotoDocument.LoadAsync(client,saved);reopened.SetDraft(new Dictionary<string,string>{{"XMP-photoshop:City",""}});
  var clearedFolder=Path.Combine(folder,"cleared");Directory.CreateDirectory(clearedFolder);
  var cleared=await client.ReadAsync(await MetadataCopy.SaveAsync(client,reopened,clearedFolder));
  Check(!cleared.TryGetProperty("XMP-photoshop:City",out _));Check(cleared.GetProperty("XMP-photoshop:Country").ToString()=="日本");
  photo.ClearDraft();Check(photo.Draft.Count==0);
  Console.WriteLine($"{count} manual-region copy/readback/atomic validation assertions passed; originals unchanged.");
 }
}
