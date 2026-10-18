using PhotoTrail.Windows;

static class SaveOwnershipChecks
{
 internal static async Task RunAsync() {
  var root=Path.Combine(Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")!,"ownership-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  Environment.SetEnvironmentVariable("PHOTOTRAIL_INPLACE_HISTORY",Path.Combine(root,"history"));
  var source=Path.Combine(root,"source.jpg");File.Copy(Environment.GetEnvironmentVariable("PHOTOTRAIL_OWNERSHIP_JPEG")!,source);
  var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);
  var a=await PhotoDocument.LoadAsync(client,source);var alias=await PhotoDocument.LoadAsync(client,source);a.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","owned"}});
  var plan=SavePlan.Prepare([a],SaveMode.Inplace,SaveScope.All,"",[a]);if(plan.Items.Length!=1)throw new Exception("single owner rejected");Console.WriteLine("PASS single actual input owner");
  try{SavePlan.Prepare([a],SaveMode.Inplace,SaveScope.All,"",[a,alias]);throw new Exception("second input owner accepted");}catch(IOException){Console.WriteLine("PASS same physical target owned by another photo refused");}
  File.Copy(source,Path.Combine(root,"other.jpg"));var b=await PhotoDocument.LoadAsync(client,Path.Combine(root,"other.jpg"));b.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","other"}});
  plan=SavePlan.Prepare([a,b],SaveMode.Inplace,SaveScope.All,"",[a,b]);if(plan.Items.Length!=2)throw new Exception("distinct owners rejected");Console.WriteLine("PASS distinct target owners accepted");
  if(await PhotoDocument.HashAsync(source)!=a.SourceHash)throw new Exception("preparation wrote source");Console.WriteLine("PASS preparation leaves source SHA unchanged");
 }
}
