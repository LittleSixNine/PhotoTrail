using PhotoTrail.Windows;
static class RenamePresetChecks
{
    public static void Run()
    {
        var count=0; void Check(bool value) { if(!value)throw new Exception("Rename preset assertion failed");count++; }
        void Reject(string json) {try{RenameRulesPreset.Decode(json);throw new Exception("Invalid preset accepted");}catch(ArgumentException){count++;}}
        var text="前缀|旅行_\r\n替换|旧|新\n序号|3|2|4";
        var preset=RenameRulesPreset.Decode(RenameRulesPreset.Encode(text,true));Check(preset.Rules==text&&preset.SortByName);
        Check(RenamePlan.Apply("旧.jpg",RenamePlan.ParseRules(preset.Rules),1)=="旅行_新0005.jpg");
        Check(!RenameRulesPreset.Decode(RenameRulesPreset.Encode("upper\nsuffix|_ok",false)).SortByName);
        Check(RenamePlan.ParseRules("\n\r\n").Count==0);
        foreach(var json in new[]{"{","[]","{}","{\"version\":2,\"rules\":\"upper\",\"sortByName\":false}","{\"version\":1,\"rules\":3,\"sortByName\":false}","{\"version\":1,\"rules\":\"upper\",\"sortByName\":\"false\"}","{\"version\":1,\"rules\":\"upper\",\"sortByName\":false,\"extra\":0}","{\"version\":1,\"rules\":\"upper\",\"rules\":\"lower\",\"sortByName\":false}"})Reject(json);
        foreach(var rules in new[]{"序号|0|0|3","replace||x","unknown","upper|extra","set|CON","prefix|../","prefix|"+new string('x',257),string.Join("\n",Enumerable.Repeat("upper",65)),"prefix|a\t"})
        {try{RenameRulesPreset.Encode(rules,false);throw new Exception("Invalid rules accepted");}catch(ArgumentException){count++;}}
        Reject(new string(' ',RenameRulesPreset.MaximumBytes+1));
        Check(RenameRulesPreset.Decode("\ufeff"+RenameRulesPreset.Encode("prefix|中文_",false)).Rules=="prefix|中文_");
        Console.WriteLine($"{count} rename preset/parser assertions passed; no files renamed.");
    }
}
