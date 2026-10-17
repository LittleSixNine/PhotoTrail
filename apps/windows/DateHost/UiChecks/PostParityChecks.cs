using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task PostParityChecks(){
  await ImportDone();var list=Control<ListBox>("Photos");list.SelectAll();Control<ComboBox>("InspectorView").SelectedIndex=1;await Responsive();
  var fields=InspectorRows().Where(r=>r.EditTag=="IFD0:Model").Take(1).ToArray();Check(fields.Length==1,"parity-actual-model-field-present");
  M2Invoke("OpenWorkflowFields",(object)fields);await Responsive();var editor=(Window)Field("metadataWindow")!;
  T Find<T>(string id)where T:DependencyObject=>M2Children(editor).OfType<T>().Single(x=>AutomationProperties.GetAutomationId(x)==id);
  var brands=Find<ComboBox>("MetadataDeviceBrand");Check(brands.Items.Count==115,"parity-fixed-Mac-115-device-brands");brands.SelectedItem="Sony";await Responsive();
  Find<TextBox>("MetadataDeviceSearch").Text="ILCE-1M2";await Responsive();var models=Find<ComboBox>("MetadataDeviceModel");Check(models.Items.Count==2,"parity-device-product-and-metadata-choices");models.SelectedIndex=1;await Responsive();
  var operations=(System.Collections.IEnumerable)Field("presetOperations")!;var op=operations.Cast<MetadataOperation>().Single();Check(op.Tag=="IFD0:Model"&&op.Value=="ILCE-1M2","parity-device-choice-fills-current-field-only");
  await PauseEvidence("device-catalogue-current-field");
  var box=M2Children((StackPanel)Field("workflowCards")!).OfType<TextBox>().Single(x=>AutomationProperties.GetName(x)=="参数（列表每行一项）");box.Text="custom model 0001";await Responsive();Check(operations.Cast<MetadataOperation>().Single().Value=="custom model 0001","parity-custom-device-input-preserved");
  M2FinishOwnTestInput();editor.Close();await Responsive();
  list.SelectAll();Control<ComboBox>("InspectorView").SelectedIndex=1;await Responsive();fields=InspectorRows().Where(r=>r.EditTag=="ExifIFD:Flash").Take(1).ToArray();Check(fields.Length==1,"parity-actual-flash-field-present");M2Invoke("OpenWorkflowFields",(object)fields);await Responsive();editor=(Window)Field("metadataWindow")!;
  var flash=Find<ComboBox>("MetadataFlashPreset");Check(flash.Items.Count==8,"parity-eight-fixed-Mac-flash-presets");flash.SelectedValue="65";await Responsive();Check(((System.Collections.IEnumerable)Field("presetOperations")!).Cast<MetadataOperation>().Single().Value=="65","parity-flash-preset-keeps-numeric-code");
  await PauseEvidence("flash-common-state-65");
  foreach(var row in list.Items.Cast<object>())Check(Doc(row).Draft.Count==0,"parity-picker-does-not-apply-or-write");
  M2FinishOwnTestInput();editor.Close();
  File.WriteAllText(Path.Combine(folder,"postparity-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
}
