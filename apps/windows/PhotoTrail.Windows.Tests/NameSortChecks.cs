using PhotoTrail.Windows;
using System.Text.Json;

static class NameSortChecks
{
    internal static void Run()
    {
        var results=new List<object>();
        RenameGroup Group(string name,int index)=>new(index.ToString(),[new(Path.Combine(Path.GetTempPath(),index.ToString(),name),new Dictionary<string,string>())]);
        void Check(bool value,string name){results.Add(new{name,passed=value});if(!value)throw new Exception(name);}
        var vectors=new[]{
            new[]{"missing.jpg","plain.jpg","e\u0301-early.jpeg"},
            new[]{"A.jpg","B.jpg","a.jpg","b.jpg"},
            new[]{"e.jpg","z.jpg","é.jpg"},
            new[]{"file001.jpg","file01.jpg","file1.jpg","file10.jpg","file2.jpg"},
            new[]{"!.jpg","-.jpg","_.jpg","a.jpg"},
            new[]{"👩.jpg","👩‍💻.jpg","😀.jpg","\ue000.jpg"}
        };
        foreach(var names in vectors)foreach(bool descending in new[]{false,true}){
            var groups=names.Reverse().Select(Group).ToArray();var paths=groups.Select(g=>g.Leader.Path).ToArray();
            var actual=RenameOrder.Ordered(groups,new("name",descending)).Select(g=>g.Name);
            Check(actual.SequenceEqual(descending?names.Reverse():names),"name-vector-"+results.Count);
            Check(groups.Select(g=>g.Leader.Path).SequenceEqual(paths),"original-codepoints-unchanged-"+results.Count);
        }
        foreach(var names in new[]{new[]{"é.jpg","e\u0301.jpg"},new[]{"가.jpg","가.jpg"},new[]{"a\u0323\u0301.jpg","a\u0301\u0323.jpg"}})
        foreach(bool descending in new[]{false,true}){
            var groups=names.Select(Group).ToArray();Check(RenameOrder.Ordered(groups,new("name",descending)).Select(g=>g.Id).SequenceEqual(groups.Select(g=>g.Id)),"canonical-stable-tie-"+results.Count);
        }
        var input=vectors[0].Reverse().Select(Group).ToArray();
        Check(RenameOrder.Ordered(input,new("input")).SequenceEqual(input)&&RenameOrder.Ordered(input,new("input",true)).SequenceEqual(input.Reverse()),"input-semantics");
        Check(RenameOrder.Ordered(input,new("manual",true)).SequenceEqual(input),"manual-semantics");
        var number=new[]{"file10.jpg","file2.jpg"}.Select(Group).ToArray();
        Check(RenameOrder.Ordered(number,new("natural"))[0].Name=="file2.jpg","natural-semantics");
        var pair=new RenameGroup("pair",[new(Path.Combine(Path.GetTempPath(),"z.jpg"),new Dictionary<string,string>()),new(Path.Combine(Path.GetTempPath(),"a.jpeg"),new Dictionary<string,string>())]){Settings=new(){SourceExtensions="jpeg,jpg"}};
        Check(RenameOrder.Ordered([Group("m.jpg",2),pair],new("name"))[0]==pair&&pair.Members[0].Name=="z.jpg","leader-priority-members-not-reordered");
        if(Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") is {} output){Directory.CreateDirectory(output);File.WriteAllText(Path.Combine(output,"name-sort-vectors.json"),JsonSerializer.Serialize(new{kind="Windows model; only first vector has supplied Mac runtime evidence",vectors,results},new JsonSerializerOptions{WriteIndented=true}));}
        Console.WriteLine($"{results.Count} name sort checks passed.");
    }
}
