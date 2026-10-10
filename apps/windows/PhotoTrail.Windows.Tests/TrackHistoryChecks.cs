using PhotoTrail.Windows;
static class TrackHistoryChecks
{
 public static void Run()
 {
  var folder=Path.Combine(Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")??Path.GetTempPath(),"track-history-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
  var file=Path.Combine(folder,"history.json");var a=Path.Combine(folder,"不存在的中文.gpx");var b=Path.Combine(folder,"b.KML");var count=0;
  void Check(bool value){if(!value)throw new Exception("History assertion failed");count++;}
  void Reject(Action action){try{action();throw new Exception("Invalid history accepted");}catch(Exception e) when(e is ArgumentException or InvalidDataException or System.Text.Json.JsonException){count++;}}
  Check(TrackHistory.Read(file).Length==0);TrackHistory.Save(file,[a,b]);Check(TrackHistory.Read(file).SequenceEqual(new[]{a,b}));Check(!File.Exists(a));
  Check(TrackHistory.Remember([a,b],b).SequenceEqual(new[]{b,a}));Check(TrackHistory.Remember([a],a.ToUpperInvariant()).Length==1);
  var many=Enumerable.Range(0,25).Select(i=>Path.Combine(folder,$"{i}.kmz")).ToArray();Check(TrackHistory.Remember(many,a).Length==20);
  var before=File.ReadAllBytes(file);Reject(()=>TrackHistory.Save(file,["relative.gpx"]));Check(File.ReadAllBytes(file).SequenceEqual(before));
  Reject(()=>TrackHistory.Save(file,[a,a.ToUpperInvariant()]));Reject(()=>TrackHistory.Save(file,[Path.Combine(folder,"a.txt")]));Reject(()=>TrackHistory.Save(file,many));Reject(()=>TrackHistory.Save(file,[a+"\n"]));
  foreach(var text in new[]{"{","null","[null]","[3]","[\"relative.gpx\"]",new string(' ',TrackHistory.MaximumBytes+1)}){File.WriteAllText(file,text);Reject(()=>TrackHistory.Read(file));Check(File.ReadAllText(file)==text);}
  TrackHistory.Save(file,[a]);Check(TrackHistory.Read(file).Single()==a);Check(Directory.GetFiles(folder,".recent-tracks-*").Length==0);
  var c=Path.Combine(folder,"c.gpx");TrackHistory.RememberAndSave(file,b);TrackHistory.RememberAndSave(file,c);
  Check(TrackHistory.Read(file).SequenceEqual(new[]{c,b,a}));
  Check(TrackHistory.RememberAndSave(file,b.ToUpperInvariant()).SequenceEqual(new[]{b.ToUpperInvariant(),c,a}));
  var snapshotText=File.ReadAllText(file);
  using(var snapshot=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read|FileShare.Delete))
  {
   TrackHistory.RememberAndSave(file,c);using var reader=new StreamReader(snapshot);Check(reader.ReadToEnd()==snapshotText);
  }
  var gateName="Local\\PhotoTrail.TrackHistory."+Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(Path.GetFullPath(file).ToUpperInvariant())));
  using(var gate=new Mutex(false,gateName))
  {
   gate.WaitOne();var heldBytes=File.ReadAllBytes(file);
   try{try{Task.Run(()=>TrackHistory.RememberAndSave(file,b)).GetAwaiter().GetResult();throw new Exception("Contended history lock accepted");}catch(IOException){Check(File.ReadAllBytes(file).SequenceEqual(heldBytes));}}
   finally{gate.ReleaseMutex();}
   Exception? orphanError=null;var orphan=new Thread(()=>{try{gate.WaitOne();}catch(Exception e){orphanError=e;}}){IsBackground=true};orphan.Start();
   if(!orphan.Join(10_000) || orphanError is not null)throw new Exception("Cannot establish abandoned lock",orphanError);
   Check(TrackHistory.RememberAndSave(file,c).First()==c);
  }  var workers=new List<System.Diagnostics.Process>();var additions=Enumerable.Range(0,12).Select(i=>Path.Combine(folder,$"parallel-{i}.gpx")).ToArray();
  try
  {
   for(var i=0;i<4;i++)
   {
    var info=new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true,RedirectStandardError=true};
    info.ArgumentList.Add("--history-remember");info.ArgumentList.Add(file);
    foreach(var path in additions.Skip(i*3).Take(3))info.ArgumentList.Add(path);
    workers.Add(System.Diagnostics.Process.Start(info)??throw new Exception("Cannot start history worker"));
   }
   foreach(var worker in workers){if(!worker.WaitForExit(10_000))throw new Exception("History worker timeout");if(worker.ExitCode!=0)throw new Exception(worker.StandardError.ReadToEnd());}
   var merged=TrackHistory.Read(file);Check(merged.Length==15);Check(additions.All(path=>merged.Contains(path)));Check(new[]{a,b,c}.All(path=>merged.Contains(path,StringComparer.OrdinalIgnoreCase)));
  }
  finally{foreach(var worker in workers){if(!worker.HasExited)worker.Kill(entireProcessTree:true);worker.Dispose();}}
  foreach(var path in many)TrackHistory.RememberAndSave(file,path);Check(TrackHistory.Read(file).SequenceEqual(many.Reverse().Take(20)));
  File.WriteAllText(file,"{");Reject(()=>TrackHistory.RememberAndSave(file,b));Check(File.ReadAllText(file)=="{");
  Check(Directory.GetFiles(folder,".recent-tracks-*").Length==0);  Console.WriteLine($"{count} track history assertions passed: {folder}");
 }
}
