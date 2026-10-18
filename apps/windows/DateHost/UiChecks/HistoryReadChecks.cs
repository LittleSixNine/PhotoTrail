using System.IO;
using System.Text.Json;
using PhotoTrail.Windows;

static partial class Program
{
 static void R3HistoryReadChecks(string output) {
  Environment.SetEnvironmentVariable("PHOTOTRAIL_RENAME_COUNTERS",Path.Combine(output,"counters.json"));
  var original=Environment.GetEnvironmentVariable("PHOTOTRAIL_HISTORY_FIXTURE")!;
  var paths=Directory.GetFiles(original,"inplace-*.jsonl");if(paths.Length!=1)throw new Exception("Expected isolated one-file completed history");
  Environment.SetEnvironmentVariable("PHOTOTRAIL_INPLACE_HISTORY",original);var record=InplaceHistory.Read(paths[0]);var bytes=File.ReadAllBytes(paths[0]);
  var mutations=new[]{record with{Photo=record.Photo+".other"},record with{Canonical=record.Canonical+".other"},record with{BackupRoot=record.BackupRoot+".other"},record with{Stage=record.Stage+".other"},record with{SourceHash=new string('0',64)},record with{Revision=record.Revision+1},record with{Fields=new(){{"XMP-dc:Title","tampered"}}},record with{Phase="invalid"}};
  int count=0;Directory.CreateDirectory(output);
  foreach(var mutation in mutations) {
   var directory=Path.Combine(output,"mutation-"+count);Directory.CreateDirectory(directory);Environment.SetEnvironmentVariable("PHOTOTRAIL_INPLACE_HISTORY",directory);var path=InplaceHistory.PathFor(record.Id);File.WriteAllBytes(path,bytes);File.AppendAllText(path,JsonSerializer.Serialize(mutation)+"\n");
   bool refused=false;try{InplaceHistory.ReadAll();}catch(InvalidDataException){refused=true;}if(!refused)throw new Exception("Changed historical identity/shape accepted "+count);Console.WriteLine("PASS changed historical identity/shape rejected "+count++);
  }
  var pending=Path.Combine(output,"pending");Directory.CreateDirectory(pending);Environment.SetEnvironmentVariable("PHOTOTRAIL_INPLACE_HISTORY",pending);File.WriteAllBytes(InplaceHistory.PathFor(record.Id),bytes);InplaceHistory.Append(record with{Phase="unknown"});
  bool blocked=false;try{InplaceHistory.RequireClear([record.Target]);}catch(IOException){blocked=true;}if(!blocked)throw new Exception("unknown no longer blocks writes");Console.WriteLine("PASS unknown still blocks writes");
  Environment.SetEnvironmentVariable("PHOTOTRAIL_INPLACE_HISTORY",original);if(!File.ReadAllBytes(paths[0]).SequenceEqual(bytes))throw new Exception("Original history changed");Console.WriteLine("PASS original history byte identity preserved");
 }
}
