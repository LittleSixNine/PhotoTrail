using PhotoTrail.Windows;
static class CommonFieldsChecks
{
 public static async Task RunAsync(ExifToolClient client,string fixtures,string output)
 {
  var folder=Path.Combine(output,"common-fields-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);var source=Path.Combine(folder,"source.jpg");File.Copy(Path.Combine(fixtures,"aligned.jpg"),source);
  await client.RunAsync(["-charset","filename=UTF8","-overwrite_original","-XMP-dc:Rights-fr=droits conservés","-XMP-dc:Rights-x-default=old rights","-XMP-iptcCore:CountryCode=CHN","--",source]);
  var photo=await PhotoDocument.LoadAsync(client,source);var count=0;void Check(bool value){if(!value)throw new Exception("Common field assertion failed");count++;}
  void Reject(Action action){try{action();throw new Exception("Invalid common field accepted");}catch(ArgumentException){count++;}}
  var changes=new Dictionary<string,string>{{"XMP-dc:Rights","版权中文\n第二行"},{"XMP-xmp:Rating","5"},{"XMP-xmp:Label","Blue 自定义"},{"XMP-tiff:Make","Windows 测试制造商"},{"XMP-tiff:Model","相机 =@literal, 型号"},{"XMP-aux:Lens","镜头 50mm"},{"XMP-aux:LensSerialNumber","0000456"},{"XMP-exif:DateTimeDigitized","2024:02:29 12:34:56.123456789+09:00"},{"XMP-xmp:CreateDate","2025:01:02 03:04:05Z"},{"XMP-xmp:ModifyDate","2026:10:10 09:08:07"}};
  var numericChanges=new Dictionary<string,string>{{"XMP-exif:ExposureTime","1/125"},{"XMP-exif:FNumber","2.8"},{"XMP-exif:ISO","00800"},{"XMP-exif:FocalLength","35.0"},{"XMP-exif:ExposureCompensation","-1/3"},{"XMP-exif:ExposureProgram","3"},{"XMP-exif:WhiteBalance","1"}};
  foreach(var field in numericChanges)changes.Add(field.Key,field.Value);
  bool Same(string tag,string actual,string expected)=>PhotoDocument.NumericRange(tag) is null ? actual==expected : Math.Abs(PhotoDocument.CheckedNumber(tag,actual)-PhotoDocument.CheckedNumber(tag,expected)) <= Math.Max(1e-12,Math.Abs(PhotoDocument.CheckedNumber(tag,expected))*1e-9);
  foreach(var field in numericChanges)
  {
   var range=PhotoDocument.NumericRange(field.Key)!.Value;
   foreach(var valid in new[]{field.Value,range.Minimum.ToString(System.Globalization.CultureInfo.InvariantCulture),range.Maximum.ToString(System.Globalization.CultureInfo.InvariantCulture),""}){PhotoDocument.ValidateChanges(new Dictionary<string,string>{{field.Key,valid}});Check(true);}
   foreach(var invalid in new[]{"NaN","Infinity","1e309","1/0","1/Infinity","NaN/1","1/2/3","文字",(range.Minimum-1).ToString(System.Globalization.CultureInfo.InvariantCulture),(range.Maximum+1).ToString(System.Globalization.CultureInfo.InvariantCulture)})Reject(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{field.Key,invalid}}));
   if(range.Integer)Reject(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{field.Key,"1.5"}}));
   Check(MetadataClipboard.Prepare(field.Value,new[]{field.Key})[field.Key]==field.Value);
  }
  Check(PhotoDocument.WriteTag("XMP-dc:Rights")=="XMP-dc:Rights-x-default");Check(PhotoDocument.BaseTag("XMP-dc:Rights-fr")=="XMP-dc:Rights-fr");
  foreach(var rating in new[]{"","-1","0","1","2","3","4","5"}){PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"XMP-xmp:Rating",rating}});Check(true);}
  foreach(var rating in new[]{"6","-2","3.5","3.0","+3"," 3","NaN"})Reject(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"XMP-xmp:Rating",rating}}));
  foreach(var label in new[]{new string('x',257),"x\ny"})Reject(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"XMP-xmp:Label",label}}));Reject(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"XMP-dc:Rights","\ud800"}}));
  var dateTags=new[]{"XMP-exif:DateTimeDigitized","XMP-xmp:CreateDate","XMP-xmp:ModifyDate"};
  foreach(var tag in dateTags)
  {
   foreach(var invalid in new[]{"2023:02:29 01:02:03","2026:10:10 01:02:03+14:01","2026:10:10 01:02:03.1234567890","not a date"})Reject(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{tag,invalid}}));
   PhotoDocument.ValidateChanges(new Dictionary<string,string>{{tag,""}});Check(true);
   Check(MetadataClipboard.Prepare(changes[tag],new[]{tag})[tag]==changes[tag]);
  }
  var cameraTags=new[]{"XMP-tiff:Make","XMP-tiff:Model","XMP-aux:Lens","XMP-aux:LensSerialNumber"};
  Check(MetadataClipboard.Prepare("000001",cameraTags).Values.All(value=>value=="000001"));
  foreach(var tag in cameraTags)Reject(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{tag,new string('x',8193)}}));  var preset=MetadataPreset.Decode(MetadataPreset.Create("版权评分标签",changes).Encode());Check(preset.Changes.SequenceEqual(changes));Check(MetadataClipboard.Prepare("3",new[]{"XMP-xmp:Rating"})["XMP-xmp:Rating"]=="3");
  photo.SetDraft(changes);Check(photo.Draft["XMP-exif:ExposureTime"]=="0.008" && photo.Draft["XMP-exif:ISO"]=="800" && photo.Draft["XMP-exif:FocalLength"]=="35");var target=Path.Combine(folder,"out");Directory.CreateDirectory(target);var copied=await MetadataCopy.SaveAsync(client,photo,target);var saved=await PhotoDocument.LoadAsync(client,copied);foreach(var field in changes)Check(Same(field.Key,saved.Value(field.Key),field.Value));
  Check(saved.Embedded.GetProperty("XMP-dc:Rights-fr").ToString()=="droits conservés");Check(await PhotoDocument.HashAsync(source)==photo.SourceHash);
  Check(await MetadataCopy.JpegPixelsAsync(source)==await MetadataCopy.JpegPixelsAsync(copied));
  Check(new[]{"IFD0:Make","IFD0:Model","ExifIFD:LensModel","ExifIFD:LensSerialNumber","ExifIFD:DateTimeOriginal","ExifIFD:CreateDate","IFD0:ModifyDate","ExifIFD:ExposureTime","ExifIFD:FNumber","ExifIFD:ISO","ExifIFD:FocalLength","ExifIFD:ExposureCompensation","ExifIFD:ExposureProgram","ExifIFD:WhiteBalance"}.All(tag=>!photo.Embedded.TryGetProperty(tag,out var original) || saved.Embedded.TryGetProperty(tag,out var actual) && original.GetRawText()==actual.GetRawText()));  var snapshot=MetadataCsv.Snapshot([saved]);Check(MetadataCsv.Export(snapshot).Contains("XMP-dc:Rights-x-default"));Check(MetadataCsv.Load(MetadataCsv.Export(snapshot),snapshot).Changes.Count==0);
  var packet=Path.Combine(folder,"fields.xmp");await MetadataXmp.ExportAsync(client,saved,packet);var imported=await MetadataXmp.ImportAsync(client,packet);foreach(var field in changes)Check(Same(field.Key,imported.Changes[field.Key],field.Value));Check(imported.IgnoredTags.Contains("XMP-dc:Rights-fr"));
  saved.SetDraft(changes.Keys.ToDictionary(tag=>tag,_=>""));var clear=Path.Combine(folder,"clear");Directory.CreateDirectory(clear);var cleared=await PhotoDocument.LoadAsync(client,await MetadataCopy.SaveAsync(client,saved,clear));Check(changes.Keys.All(tag=>cleared.Value(tag)==""));Check(cleared.Embedded.GetProperty("XMP-dc:Rights-fr").ToString()=="droits conservés");
  var raw=await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"sidecar.DNG"));var cameraChanges=cameraTags.Concat(dateTags).Concat(numericChanges.Keys).ToDictionary(tag=>tag,tag=>changes[tag]);raw.SetDraft(cameraChanges);
  var rawOutput=Path.Combine(folder,"raw-output");Directory.CreateDirectory(rawOutput);var rawCopy=await MetadataCopy.SaveAsync(client,raw,rawOutput);var rawSaved=await PhotoDocument.LoadAsync(client,rawCopy);
  foreach(var change in cameraChanges)Check(Same(change.Key,rawSaved.Value(change.Key),change.Value));
  Check(await PhotoDocument.HashAsync(rawCopy)==raw.SourceHash && await PhotoDocument.HashAsync(raw.FilePath)==raw.SourceHash && await PhotoDocument.HashAsync(raw.SidecarPath!)==raw.SidecarHash);  Console.WriteLine($"{count} common XMP field assertions passed: {folder}");
 }
}
