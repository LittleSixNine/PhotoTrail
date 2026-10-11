using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 // Hold only the production async continuation after real source hashing, not its I/O or outcome.
 sealed class HeldContext(SynchronizationContext owner):SynchronizationContext
 {
  public readonly TaskCompletionSource<(SendOrPostCallback,object?)> Posted=new(TaskCreationOptions.RunContinuationsAsynchronously);
  bool released;
  public override void Post(SendOrPostCallback callback,object? state){if(released)owner.Post(callback,state);else Posted.TrySetResult((callback,state));}
  public void Release(){released=true;var (callback,state)=Posted.Task.Result;owner.Post(callback,state);}
 }
 static async Task RunTrackLateFailures()
 {
  for(int i=0;i<1200&&(Control<ListBox>("Photos").Items.Count<3||Control<ComboBox>("TrackList").Items.Count<1);i++)await Task.Delay(10);
  await TrackWait();Control<ListBox>("Photos").SelectedItem=Control<ListBox>("Photos").Items[0];
  var source=Snapshot();var bytes=File.ReadAllBytes(source.Path);
  foreach(string method in new[]{"MatchTrack","AddGpsDraft"}){
   File.WriteAllBytes(source.Path,bytes);Control<TextBox>("MatchTimeValue").Text=source.Data.Segments[0][0].Time!.Value.ToString("O");await TrackMatch();Check(Control<Button>("GpsDraftButton").IsEnabled,"initial-valid-match-"+method);
   File.AppendAllText(source.Path,new string(' ',1024*1024));
   var owner=SynchronizationContext.Current!;var gate=new HeldContext(owner);
   try{SynchronizationContext.SetSynchronizationContext(gate);Action(method);}finally{SynchronizationContext.SetSynchronizationContext(owner);}
   await gate.Posted.Task.WaitAsync(TimeSpan.FromSeconds(15));Check(!gate.Posted.Task.IsFaulted,"real-hash-completed-old-continuation-held-"+method);
   var point=new MapPoint(11,22);typeof(MainWindow).GetField("currentPreview",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,point);
   typeof(MainWindow).GetMethod("UpdateGpsButton",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);
   Control<TextBlock>("MatchResult").Text="new location ready";Control<TextBlock>("Status").Text="new request status";
   gate.Release();await window.Dispatcher.InvokeAsync(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);await TrackWait();
   Check(ReferenceEquals(Field("currentPreview"),point)&&Control<Button>("GpsDraftButton").IsEnabled&&Control<TextBlock>("MatchResult").Text=="new location ready"&&Status=="new request status","old-source-failure-preserves-new-preview-qualification-and-status-"+method);
   Check(Control<ListBox>("Photos").Items.Cast<object>().Select(Doc).All(d=>d.Draft.Count==0),"no-GPS-draft-on-failed-old-request-"+method);
  }
  File.WriteAllBytes(source.Path,bytes);Check(await PhotoDocument.HashAsync(source.Path)==source.SourceHash,"track-source-restored-hash");
  File.WriteAllText(Path.Combine(folder,"track-late-failure-results.json"),JsonSerializer.Serialize(new{evidence,passed=evidence.Count},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("TRACK_LATE_FAILURE_WPF="+evidence.Count);
 }
}
