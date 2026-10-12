using System.Diagnostics;
using System.Text;
using System.Text.Json;
var input=await Console.In.ReadToEndAsync();using var json=JsonDocument.Parse(input);
var items=json.RootElement.GetProperty("items");const string trigger="2024:02:29 11:22:33.123456789Z";
if(!items.EnumerateArray().Any(item=>item.TryGetProperty("text",out var value)&&value.GetString()==trigger)) {
    using var child=new Process{StartInfo=new(Environment.GetEnvironmentVariable("PHOTOTRAIL_CHECK_REAL_HOST")!){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardInputEncoding=new UTF8Encoding(false)}};
    child.Start();var output=child.StandardOutput.ReadToEndAsync();var error=child.StandardError.ReadToEndAsync();await child.StandardInput.WriteAsync(input);child.StandardInput.Close();await child.WaitForExitAsync();Console.Write(await output);Console.Error.Write(await error);return child.ExitCode;
}
var mode=Environment.GetEnvironmentVariable("PHOTOTRAIL_CHECK_HOST_FAULT")??"malformed";
if(mode=="timeout"){await Task.Delay(45000);return 0;}if(mode=="nonzero")return 17;
if(mode=="malformed"){Console.Write("{");return 0;}if(mode=="output-limit"){Console.Write(new string('x',1048577));return 0;}
var source=new{commit="63fb9404ec5f0862df90a000f5dd1c4b81509900",path="Packages/PhotoTrailDateCore/Sources/PhotoTrailDateCore/MetadataDateEdit.swift",sha256="593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc"};
var root=new Dictionary<string,object?>{{"version",mode=="version"?"invalid":"date-isolated-v1"},{"id",json.RootElement.GetProperty("id").GetString()},{"source",source},{"results",mode=="result-count"?Array.Empty<object>():items.EnumerateArray().Select(item=>(object)new{id=item.GetProperty("id").GetString(),values=new[]{trigger}}).ToArray()},{"computeMs",0}};
if(mode=="unknown")root["unknown"]=true;Console.Write(JsonSerializer.Serialize(root));return 0;
