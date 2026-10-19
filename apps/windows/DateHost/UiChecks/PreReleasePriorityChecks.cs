using System.IO;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task PreReleasePriorityChecks()
 {
  await ImportDone();var photos=Control<ListBox>("Photos");photos.SelectAll();Control<TabControl>("WorkspaceTabs").SelectedIndex=2;
  var originals=photos.Items.Cast<object>().Select(Doc).ToDictionary(d=>d.FilePath,d=>d.SourceHash);
  foreach(var (extensions,leader) in new[]{("jpeg,jpg","jpeg"),("jpg,jpeg","jpg")})
  {
   var before=RenameCounters.Read(RenameCounters.DefaultPath);
   var rule=new RenameRule("action"){Action="number-begin",Counter=1,Padding=3,Start=1,Step=1};
   var order=new RenameOrderSettings("name"){SourceExtensions=extensions,TargetExtensions="xmp",Conflict="numbers",DatePriority="XMP-xmp:CreateDate\nExifIFD:DateTimeOriginal"};
   var scheme=new RenameScheme(Guid.NewGuid(),"Priority execution",RenamePlan.EncodeEditorRules([rule]),order,"");
   M3Call("SetSchemeEditor",scheme);Action("RefreshRenameOrder");await RenameWait();
   Check(((RenameGroup[])Field("renameGroups")!).Single(g=>g.Members.Count==3).Leader.Extension==leader,"priority-actual-leader-"+leader);
   Check(RenameCounters.Read(RenameCounters.DefaultPath).Revision==before.Revision,"priority-parameter-preview-does-not-reset-counter-"+leader);
   Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is RenamePlan,"priority-freeze-"+leader);
   Control<TextBox>("RenameSources").Text=extensions=="jpeg,jpg"?"jpg,jpeg":"jpeg,jpg";await Responsive();
   Check(Field("frozenRenamePlan")is null&&RenameCounters.Read(RenameCounters.DefaultPath).Revision==before.Revision,"priority-reversal-invalidates-freeze-no-counter-consumption-"+leader);
   M3Call("SetSchemeEditor",scheme);Action("RefreshRenameOrder");await RenameWait();Action("FreezeRename");await RenameWait();var plan=(RenamePlan)Field("frozenRenamePlan")!;
   Check(plan.Files.Count==5&&plan.CounterUse!.Advances[1]==before.Values[1]+3,"priority-three-groups-five-physical-files-counter-bound-"+leader);
   var executed=await RenameExecutor.ExecuteAsync(plan,Path.Combine(folder,leader+"-journal"));
   Check(executed.Complete&&RenameCounters.Read(RenameCounters.DefaultPath).Values[1]==plan.CounterUse!.Advances[1],"priority-execution-counter-exact-"+leader);
   foreach(var file in plan.Files)Check(await PhotoDocument.HashAsync(file.Target)==file.Hash,"priority-independent-output-name-SHA-"+leader);
   var after=RenameCounters.Read(RenameCounters.DefaultPath);var restored=await RenameExecutor.RestoreAsync(executed.Journal,Path.Combine(folder,leader+"-journal"));
   Check(restored.Complete&&RenameCounters.Read(RenameCounters.DefaultPath).Revision==after.Revision,"priority-restore-does-not-rewind-counter-"+leader);
   foreach(var file in originals)Check(await PhotoDocument.HashAsync(file.Key)==file.Value,"priority-source-restored-SHA-"+leader);
  }
  M3Set("frozenRenamePlan",null);M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));
  SaveResult("pre-release-priority.json",new{kind="production DLL priority controls and actual execute/restore, separate from native keyboard"});
 }
}
