using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task PreReleaseMusicChecks()
 {
  await ImportDone();var list=Control<ListBox>("Photos");list.SelectAll();Check(list.Items.Count==1,"music-one-real-XMP-JPEG");
  var doc=Doc(list.Items[0]);var original=await PhotoDocument.HashAsync(doc.FilePath);Control<TabControl>("WorkspaceTabs").SelectedIndex=2;
  var actions=new[]{"music-set","music-end","music-begin","music-before","music-after","music-position"};
  var input=new RenameInput(doc.FilePath,doc.Embedded.EnumerateObject().ToDictionary(p=>p.Name,p=>PhotoDocument.Text(p.Value)));
  foreach(var action in actions)
  {
   var rule=new RenameRule("action","<Artist>_<Album>_<0TrackNum>_<Song>"){Action=action,Anchor="old",Position=1};
   var scheme=new RenameScheme(Guid.NewGuid(),"Music qualification",JsonSerializer.Serialize(rule),new(),"");
   M3Call("SetSchemeEditor",scheme);Action("RefreshRenameOrder");await RenameWait();
   var preview=Control<DataGrid>("RenamePreview").Items.Cast<RenameFile>().Single();
   Check(preview.NewName==RenamePlan.Apply("old.jpg",[rule],0,input.Tag),action+"-production-preview-uses-real-XMP-aliases");
   var panel=(System.Windows.Controls.Panel)Field("m3CardPanel")!;
   Check(M2Children(panel).OfType<TextBox>().Any(b=>System.Windows.Automation.AutomationProperties.GetAutomationId(b)=="M6RenameParam.Text"),action+"-real-text-parameter-control-present");
   Action("FreezeRename");await RenameWait();var plan=(RenamePlan)Field("frozenRenamePlan")!;
   Check(plan.Files.Count==1&&plan.Files[0].Hash==original,action+"-freeze-binds-original-SHA");
   var execution=await RenameExecutor.ExecuteAsync(plan,Path.Combine(folder,action+"-journal"));
   Check(execution.Complete&&await PhotoDocument.HashAsync(plan.Files[0].Target)==original,action+"-execute-independent-SHA");
   var restored=await RenameExecutor.RestoreAsync(execution.Journal,Path.Combine(folder,action+"-journal"));
   Check(restored.Complete&&await PhotoDocument.HashAsync(doc.FilePath)==original,action+"-restore-independent-SHA");
  }
  M3Set("frozenRenamePlan",null);M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));
  SaveResult("pre-release-music.json",new{kind="production DLL controls, actual JPEG metadata, file execution/restore; not native keyboard or Mac runtime"});
 }
}
