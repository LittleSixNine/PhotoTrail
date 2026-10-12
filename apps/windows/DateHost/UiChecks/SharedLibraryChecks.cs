using System.IO;
using System.Security.Cryptography;
using System.Windows.Controls;
using PhotoTrail.Windows;
static partial class Program
{
 static async Task SharedLibrary() {
  var rows=await DateCoreRows(4);Control<ListBox>("Photos").SelectAll();SelectMetadataTab("字段预设");string path=Environment.GetEnvironmentVariable("PHOTOTRAIL_METADATA_PRESETS")!;
  var oldBytes=File.ReadAllBytes(path);Check(Library().Length==1&&Control<ListBox>("PresetOperations").Items.Count==0&&Field("currentMetadataPreset")is null,"shared-old-invalid-record-restored-list-only");
  Control<ListBox>("MetadataPresetList").SelectedIndex=0;await Idle();Check(Field("currentMetadataPreset")is null&&Library().Length==1&&File.ReadAllBytes(path).SequenceEqual(oldBytes),"shared-old-invalid-record-explicit-load-refused-preserved");Check(rows.All(row=>Doc(row).Draft.Count==0),"shared-old-record-no-auto-application");
  var valid=MetadataPreset.Create("共享合法日期",new[]{new MetadataOperation("XMP-exif:DateTimeOriginal","setText","2024:02:29 11:22:33.123456789-00:00"),new MetadataOperation("XMP-exif:DateTimeDigitized","copy","XMP-exif:DateTimeOriginal")});Invoke("SetUnsavedPreset",valid);Action("SaveNewMetadataPreset");await Idle();await Responsive();Check(Library().Length==2&&Library()[0].Preset.Operations[0].Value=="1582:10:05 00:00:00","shared-library-new-date-save-retains-old-rejected-record");var saved=Library()[1];var committed=File.ReadAllBytes(path);
  Invoke("SetPresetChain",MetadataPreset.Create(valid.Name,new[]{new MetadataOperation("XMP-exif:DateTimeOriginal","setText","1582:10:05 00:00:00")}));Action("UpdateMetadataPreset");await Idle();Check(File.ReadAllBytes(path).SequenceEqual(committed)&&Library()[1].Id==saved.Id&&Control<ListBox>("PresetOperations").Items.Cast<MetadataOperation>().Single().Value=="1582:10:05 00:00:00","shared-library-invalid-new-parameter-no-write-keeps-editor");
  Invoke("SetPresetChain",saved.Preset);Action("ReloadMetadataPresets");await Idle();Check(Field("currentMetadataPreset")!.Equals(saved.Id)&&Library()[1].Preset.Operations.SequenceEqual(saved.Preset.Operations),"shared-library-explicit-reread-valid-content");
  var pathBox=Control<TextBox>("PresetPath");string bad=Path.Combine(folder,"bad-preset.json");File.WriteAllText(bad,MetadataPreset.Create("文件非法日期",new[]{new MetadataOperation("XMP-exif:DateTimeOriginal","setText","1582:10:05 00:00:00")}).Encode());pathBox.Text=bad;Action("LoadPreset");await Idle();Check(Control<ListBox>("PresetOperations").Items.Cast<MetadataOperation>().SequenceEqual(saved.Preset.Operations),"shared-preset-file-load-invalid-keeps-chain");
  Invoke("SetPresetChain",new MetadataPreset("新预设",Array.Empty<MetadataOperation>()));typeof(MainWindow).GetField("metadataPresetBaseline",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!.SetValue(window,null);DateCoreResult("r01b-library-results.json");
 }
}
