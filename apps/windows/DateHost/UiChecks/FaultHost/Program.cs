using System.Diagnostics;
using System.Text;
using System.Text.Json.Nodes;
var input=await Console.In.ReadToEndAsync();var request=JsonNode.Parse(input)!;
const string trigger="2024:02:29 11:22:33.123456789Z";
var mode=request["items"]!.AsArray().Any(item=>item?["text"]?.GetValue<string>()==trigger)?Environment.GetEnvironmentVariable("PHOTOTRAIL_CHECK_HOST_FAULT"):null;
if(mode=="timeout"){await Task.Delay(45000);return 0;}if(mode=="nonzero")return 17;
if(mode=="malformed"){Console.Write("{");return 0;}if(mode=="output-limit"){Console.Write(new string('x',1048577));return 0;}
using var child=new Process{StartInfo=new(Environment.GetEnvironmentVariable("PHOTOTRAIL_CHECK_REAL_HOST")!){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardInputEncoding=new UTF8Encoding(false)}};
child.Start();var output=child.StandardOutput.ReadToEndAsync();var error=child.StandardError.ReadToEndAsync();await child.StandardInput.WriteAsync(input);child.StandardInput.Close();await child.WaitForExitAsync();
var root=JsonNode.Parse(await output)!;
if(mode=="version")root["version"]="invalid";
if(mode=="source")root["source"]!["sha256"]="wrong";
if(mode=="result-count")root["results"]=new JsonArray();
if(mode=="unknown")root["unknown"]=true;
Console.Write(root.ToJsonString());Console.Error.Write(await error);return child.ExitCode;
