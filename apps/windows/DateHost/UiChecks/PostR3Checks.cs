using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task R3InteropChecks() {
  await ImportDone();var list=Control<ListBox>("Photos");list.SelectAll();Control<TabControl>("WorkspaceTabs").SelectedIndex=2;await Responsive();
  var exports=Environment.GetEnvironmentVariable("PHOTOTRAIL_MAC_EXPORTS")!;
  foreach(var kind in new[]{"date","numeric"}) {
   string text=File.ReadAllText(Path.Combine(exports,kind+"-mac-export.json"));var scheme=RenameSchemeLibrary.Import(text,"actual Mac");
   var counter=RenameCounters.Read(RenameCounters.DefaultPath);M3Call("SetSchemeEditor",scheme);Action("RefreshRenameOrder");await RenameWait();
   Check(RenameCounters.Read(RenameCounters.DefaultPath).Revision==counter.Revision,"R3-actual-import-does-not-reset-local-counter-"+kind);
   var preview=Control<DataGrid>("RenamePreview").Items.Cast<RenameFile>().ToArray();Check(preview.Length==3,"R3-actual-three-Mac-inputs-"+kind);
   if(kind=="date") {
    Check(preview.Single(f=>f.OriginalName.EndsWith(".jpeg",StringComparison.Ordinal)).NewName=="2024-01-15_04-20-30.jpeg","R3-NFD-name-NFC-prefix-real-Mac-parameters");
    Check(preview.Single(f=>f.OriginalName=="plain.jpg").NewName=="2024-01-15_04-20-50.jpg"&&preview.Single(f=>f.OriginalName=="missing.jpg").NewName=="missing.jpg","R3-Mac-zone-missing-disabled-output");
   }
   Action("FreezeRename");await RenameWait();var plan=(RenamePlan)Field("frozenRenamePlan")!;
   var before=plan.Files.ToDictionary(f=>f.Source,f=>(f.Hash,properties:PostProperties(f.Source)));
   var result=await RenameExecutor.ExecuteAsync(plan,Path.Combine(folder,kind+"-journal"));Check(result.Complete,"R3-actual-Mac-plan-file-execution-"+kind);
   foreach(var f in plan.Files)Check(await PhotoDocument.HashAsync(f.Target)==f.Hash,"R3-independent-output-SHA-"+kind);
   var after=RenameCounters.Read(RenameCounters.DefaultPath);
   if(kind=="numeric")Check(after.Values[1]==counter.Values[1]+3,"R3-three-numeric-consumptions-local-initial-value");
   var restored=await RenameExecutor.RestoreAsync(result.Journal,Path.Combine(folder,kind+"-journal"));Check(restored.Complete,"R3-this-record-restores-"+kind);
   foreach(var entry in before){var now=PostProperties(entry.Key);Check(await PhotoDocument.HashAsync(entry.Key)==entry.Value.Hash&&now with{Identity=entry.Value.properties.Identity,Accessed=entry.Value.properties.Accessed}==entry.Value.properties,"R3-restored-SHA-times-attributes-readable-ACL-"+kind);}
   Check(RenameCounters.Read(RenameCounters.DefaultPath).Revision==after.Revision,"R3-restore-does-not-rewind-counter-"+kind);
   var edited=(RenameScheme)M3Call("EditedScheme",Guid.NewGuid(),null)!;
   Check(edited.Order.MetadataSortTag==scheme.Order.MetadataSortTag,"R3-native-editor-preserves-optional-metadata-sort-tag");
   File.WriteAllText(Path.Combine(folder,kind+"-windows-export.json"),MacRenamePreset.Export(edited));
   File.WriteAllText(Path.Combine(folder,kind+"-execution.local.json"),JsonSerializer.Serialize(new{preview=preview.Select(f=>new{f.OriginalName,f.NewName}),counterBefore=counter.Values[1],counterAfter=after.Values[1],restored=restored.Complete}));
  }
  M3Set("frozenRenamePlan",null);M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));SaveResult("r3-interop.json",new{kind="production DLL checker; not native keyboard",counter=RenameCounters.Read(RenameCounters.DefaultPath).Values[1]});
 }
 static async Task R3F09Checks() {
  await ImportDone();Control<ListBox>("Photos").SelectAll();Control<TabControl>("WorkspaceTabs").SelectedIndex=2;await Responsive();
  var date=new RenameRule("date-set");var number=new RenameRule("action"){Action="number-end",Counter=1};
  var order=new RenameOrderSettings("shooting"){SourceExtensions="png",TargetExtensions="xmp",DatePriority="XMP-xmp:CreateDate",Conflict="numbers"};
  var scheme=new RenameScheme(Guid.NewGuid(),"R3 F09 explicit per-sidecar dates",RenamePlan.EncodeEditorRules([date,number]),order,"");
  var stages=new List<object>();
  foreach(bool reversed in new[]{false,true,false,true,false}) {
   M3Call("SetSchemeEditor",scheme with{Rules=RenamePlan.EncodeEditorRules(reversed?[number,date]:[date,number])});Action("RefreshRenameOrder");await RenameWait();
   var files=Control<DataGrid>("RenamePreview").Items.Cast<RenameFile>().ToArray();Check(files.Length==4,"R3-F09-four-physical-inputs");
   foreach(var f in files)Check(f.NewName.StartsWith(f.OriginalName.StartsWith('a')?"20240103_010203":"20240102_010203",StringComparison.Ordinal),"R3-F09-own-sidecar-date-survives-reorder");
   stages.Add(new{reversed,revision=Field("renameRevision"),rules=ReadRules(),files=files.Select(f=>new{f.OriginalName,f.NewName,f.Steps})});
   Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is RenamePlan,"R3-F09-new-freeze");
   Control<CheckBox>("RenameDescending").IsChecked=!Control<CheckBox>("RenameDescending").IsChecked;await Responsive();Check(Field("frozenRenamePlan")is null,"R3-F09-old-freeze-invalidated");
  }
  M3Call("SetSchemeEditor",scheme);Action("RefreshRenameOrder");await RenameWait();Action("FreezeRename");await RenameWait();var plan=(RenamePlan)Field("frozenRenamePlan")!;
  var hashes=plan.Files.ToDictionary(f=>f.Source,f=>f.Hash);var saved=await RenameExecutor.ExecuteAsync(plan,Path.Combine(folder,"f09-journal"));Check(saved.Complete,"R3-F09-refrozen-real-execution");
  foreach(var f in plan.Files)Check(await PhotoDocument.HashAsync(f.Target)==f.Hash,"R3-F09-executed-byte-proof");
  long consumed=RenameCounters.Read(RenameCounters.DefaultPath).Values[1];var restored=await RenameExecutor.RestoreAsync(saved.Journal,Path.Combine(folder,"f09-journal"));Check(restored.Complete,"R3-F09-own-record-restored");foreach(var f in hashes)Check(await PhotoDocument.HashAsync(f.Key)==f.Value,"R3-F09-restored-source-SHA");Check(RenameCounters.Read(RenameCounters.DefaultPath).Values[1]==consumed,"R3-F09-restore-retains-counter");
  M3Set("frozenRenamePlan",null);M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));SaveResult("r3-f09.json",new{stages,consumed,kind="production DLL checker; native reordering separate"});
  string ReadRules()=>Control<TextBox>("RenameRules").Text;
 }
}
