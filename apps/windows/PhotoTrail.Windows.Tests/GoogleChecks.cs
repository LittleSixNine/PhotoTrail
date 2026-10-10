using PhotoTrail.Windows;
using System.Text.Json;
static class GoogleChecks
{
 public static void Run()
 {
  var count=0; void Check(bool value){if(!value)throw new Exception("Google message boundary failed");count++;}
  var valid=JsonSerializer.Serialize(new {type="place",id=2,point=new MapPoint(135.77,35.01),status="OK",fields=new {country="日本",countryCode="JP",state="京都府",city="京都市",sublocation="左京区"}});
  Check(MapPlace.TryRead(MapMessage.GooglePage,valid,out var result)&&result!.Fields["city"]=="京都市");
  Check(result!.Matches(2,new(135.77,35.01)));
  Check(!result.Matches(3,new(135.77,35.01))); Check(!result.Matches(2,new(135.78,35.01))); Check(!result.Matches(2,null));
  Check(!MapPlace.TryRead(MapMessage.Page,valid,out _)); Check(!MapPlace.TryRead("https://unexpected.invalid/",valid,out _));
  foreach(var bad in new[]{"{","[]",valid.Replace("135.77","181"),valid.Replace("35.01","91"),valid.Replace("\"JP\"","\"JPN\""),valid.Replace("\"city\"","\"unknown\""),valid.Replace("\"OK\"","\"UNKNOWN\""),valid+new string(' ',4096)})Check(!MapPlace.TryRead(MapMessage.GooglePage,bad,out _));
  foreach(var status in new[]{"ZERO_RESULTS","OVER_QUERY_LIMIT","REQUEST_DENIED","INVALID_REQUEST","UNKNOWN_ERROR","ERROR"})
  {
   Check(MapPlace.TryRead(MapMessage.GooglePage,JsonSerializer.Serialize(new {type="place",id=1,point=new MapPoint(0,0),status,fields=new {}}),out _));
  }
  Check(!MapPlace.TryRead(MapMessage.GooglePage,valid.Replace("\"OK\"","\"ERROR\""),out _));
  Check(MapMessage.IsGoogleBootstrap(MapMessage.GooglePage,"{\"type\":\"google-bootstrap\"}"));
  Check(!MapMessage.IsGoogleBootstrap(MapMessage.Page,"{\"type\":\"google-bootstrap\"}"));
  Check(MapMessage.TryPoint(MapMessage.GooglePage,"{\"type\":\"point\",\"longitude\":0,\"latitude\":0}",out _));
  Console.WriteLine($"{count} Google/local-page/result freshness assertions passed without Google requests.");
 }
}
