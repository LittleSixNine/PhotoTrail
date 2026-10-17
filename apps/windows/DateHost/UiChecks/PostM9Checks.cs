using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static FileProperties PostProperties(string path){using var file=WindowsRename.Open(path);return WindowsRename.Properties(file,path);}
 static async Task PostM9Checks(){
  await ImportDone();var photos=Control<ListBox>("Photos");photos.SelectAll();Control<TabControl>("WorkspaceTabs").SelectedIndex=2;await Responsive();
  var rules=new[]{new RenameRule("action"){Action="date-set",DateFormat="yyyy-MM-dd_HH-mm-ss"},new RenameRule("action"){Action="number-end",Start=1,Step=1,Padding=2,Counter=1}};
  var order=new RenameOrderSettings("shooting"){SourceExtensions="png",TargetExtensions="xmp",DatePriority="XMP-xmp:CreateDate",Conflict="numbers"};
  var scheme=new RenameScheme(Guid.NewGuid(),"POSTM9 PNG sidecar regression",RenamePlan.EncodeEditorRules(rules),order,"");
  M3Call("SetSchemeEditor",scheme);await Responsive();Action("RefreshRenameOrder");await RenameWait();
  var groups=(RenameGroup[])Field("renameGroups")!;
  Check(groups.Length==2&&groups.All(g=>g.Leader.Extension=="png"&&g.Members.Count==2),"POSTM9-valid-PNG-XMP-custom-groups");
  Check(groups.All(g=>g.Leader.ShootingTexts().Single().StartsWith("2024:01:0",StringComparison.Ordinal)),"POSTM9-sidecar-only-date-reaches-main-member");
  await EvidenceDialog("M3InputSettings","PNG-pair-date-settings");
  await PauseEvidence("PNG-date-preview");
  var ordered=(RenameGroup[])M3Call("OrderedRenameGroups")!;Check(ordered.Select(g=>g.Name).SequenceEqual(new[]{"b.png","a.png"}),"POSTM9-sidecar-date-orders-main-PNG");
  var preview=Control<DataGrid>("RenamePreview").Items.Cast<RenameFile>().ToArray();Check(preview.Length==4&&preview.All(f=>f.NewName.StartsWith("2024-01-0",StringComparison.Ordinal)),"POSTM9-date-preview-names-both-physical-members");
  Action("FreezeRename");await RenameWait();var plan=(RenamePlan)Field("frozenRenamePlan")!;Check(plan.Files.Count==4&&plan.Files.All(f=>f.Target.Contains("2024-01-0",StringComparison.Ordinal)),"POSTM9-freeze-retains-sidecar-date-targets");
  await PauseEvidence("PNG-frozen-date-plan");
  Control<CheckBox>("RenameDescending").IsChecked=true;await Responsive();Check(Field("frozenRenamePlan")is null,"POSTM9-changed-sort-invalidates-freeze");
  M3Call("SetSchemeEditor",scheme);await Responsive();Action("RefreshRenameOrder");await RenameWait();Action("FreezeRename");await RenameWait();plan=(RenamePlan)Field("frozenRenamePlan")!;
  var before=plan.Files.ToDictionary(f=>f.Source,f=>new{f.Hash,Properties=PostProperties(f.Source)});var count=RenameCounters.Read(RenameCounters.DefaultPath);
  var result=await RenameExecutor.ExecuteAsync(plan,Path.Combine(folder,"png-rename-journal"));Check(result.Complete&&result.Files.Count==4&&result.Files.All(f=>File.Exists(f.Target)),"POSTM9-real-PNG-XMP-date-rename-executed");
  var after=RenameCounters.Read(RenameCounters.DefaultPath);Check(after.Values[1]==count.Values[1]+2,"POSTM9-counter-advances-per-logical-group");
  var restored=await RenameExecutor.RestoreAsync(result.Journal,Path.Combine(folder,"png-rename-journal"));Check(restored.Complete,"POSTM9-this-record-restores-four-physical-files");
  foreach(var pair in before)Check(await PhotoDocument.HashAsync(pair.Key)==pair.Value.Hash&&WindowsRename.SameProperties(pair.Value.Properties,PostProperties(pair.Key)),"POSTM9-restore-SHA-identity-times-attributes-ACL-"+Path.GetFileName(pair.Key));
  Check(RenameCounters.Read(RenameCounters.DefaultPath).Values[1]==after.Values[1],"POSTM9-restore-keeps-advanced-counter");
  var imported=photos.Items.Cast<object>().Select(Doc).First(d=>Path.GetFileName(d.FilePath)=="a.png");imported.SetDraft(new Dictionary<string,string>{{imported.MainDateTag,""}});Action("RefreshRenameOrder");await RenameWait();
  Check(((RenameGroup[])Field("renameGroups")!).Single(g=>g.Name=="a.png").Leader.ShootingTexts().Count()==0,"POSTM9-explicit-clear-does-not-fall-back-to-sidecar-date");imported.ClearDraft();
  M3Set("frozenRenamePlan",null);M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));
  File.WriteAllText(Path.Combine(folder,"postm9-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
}
