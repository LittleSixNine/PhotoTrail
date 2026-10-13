using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PhotoTrail.Windows;

public sealed record PhotoSortPreference([property:JsonPropertyName("field")]string Field,[property:JsonPropertyName("descending")]bool Descending);
public sealed record SettingsPreference(int TextSize=0,int Spacing=0,bool FullTagNames=true,bool RecordSearches=true,PhotoSortPreference[]? Sorts=null,bool CommonOnly=true,string[]? CommonFields=null,string BackupFolder="")
{
    public static string DefaultPath=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"PhotoTrail","Windows","settings-v1.json");
    public PhotoSortPreference[] PhotoSort=>Sorts is {Length:>0}?Sorts:[new("name",false)];
    public string[] CommonTags=>CommonFields??MetadataInspector.DefaultCommon;
    public double FontDelta=>TextSize*2*96d/72d;
    public double RowPadding=>Spacing<0?2:Spacing>0?10:6;
    public double MinimumRowHeight=>Spacing<0?30:Spacing>0?48:40;
    public static string TagLabel(string tag,bool full)=>full?tag:tag.Split(':')[0];
    public static SettingsPreference Read(string file)
    {
        if(!File.Exists(file))return new();
        try {
            using var json=ReadJson(file);var root=json.RootElement;
            if(root.ValueKind!=JsonValueKind.Object || !root.TryGetProperty("version",out var version) || !version.TryGetInt32(out var number) || number!=1)return new();
            int Choice(string key)=>root.TryGetProperty(key,out var value)&&value.ValueKind==JsonValueKind.Number&&value.TryGetInt32(out var choice)&&choice is >=-1 and <=1?choice:0;
            bool Toggle(string key)=>!root.TryGetProperty(key,out var value)||value.ValueKind!=JsonValueKind.False;
            var sorts=new List<PhotoSortPreference>();
            if(root.TryGetProperty("PhotoTrailPhotoSort.v1",out var array)&&array.ValueKind==JsonValueKind.Array)
                foreach(var item in array.EnumerateArray())
                    if(item.ValueKind==JsonValueKind.Object&&item.TryGetProperty("field",out var field)&&field.ValueKind==JsonValueKind.String&&field.GetString() is "name" or "captured" or "import"&&item.TryGetProperty("descending",out var descending)&&descending.ValueKind is JsonValueKind.True or JsonValueKind.False)
                        sorts.Add(new(field.GetString()!,descending.GetBoolean()));
            string[]? common=null;
            if(root.TryGetProperty("PhotoTrailMetadataCommonFields.v1",out var commonJson)&&commonJson.ValueKind==JsonValueKind.Array&&commonJson.EnumerateArray().All(x=>x.ValueKind==JsonValueKind.String&&x.GetString() is {Length:>2 and <=256} tag&&tag.Split(':').Length==2&&!tag.Any(char.IsControl)))common=commonJson.EnumerateArray().Select(x=>x.GetString()!).Distinct(StringComparer.Ordinal).ToArray();
            return new(Choice("PhotoTrailMetadataTextSize"),Choice("PhotoTrailMetadataSpacing"),Toggle("PhotoTrailMetadataTagNames"),Toggle("PhotoTrailRecordSearches"),sorts.ToArray(),Toggle("metadataCommonFieldsOnly"),common,root.TryGetProperty("windowsBackupFolder",out var backup)&&backup.ValueKind==JsonValueKind.String?backup.GetString()??"":"");
        }catch(Exception error)when(error is JsonException or InvalidDataException or InvalidOperationException){return new();}
    }
    public static void Save(string file,SettingsPreference settings)
    {
        if(settings.TextSize is <-1 or >1 || settings.Spacing is <-1 or >1 || settings.PhotoSort.Any(s=>s.Field is not("name" or "captured" or "import")))throw new ArgumentException("设置值无效。");
        WriteJson(file,new Dictionary<string,object>{["version"]=1,["PhotoTrailMetadataTextSize"]=settings.TextSize,["PhotoTrailMetadataSpacing"]=settings.Spacing,["PhotoTrailMetadataTagNames"]=settings.FullTagNames,["PhotoTrailRecordSearches"]=settings.RecordSearches,["PhotoTrailPhotoSort.v1"]=settings.PhotoSort,["metadataCommonFieldsOnly"]=settings.CommonOnly,["PhotoTrailMetadataCommonFields.v1"]=settings.CommonTags,["windowsBackupFolder"]=settings.BackupFolder});
    }
    internal static JsonDocument ReadJson(string file)
    {
        using var input=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read);
        if(input.Length>16384)throw new InvalidDataException("本机设置超过16KiB上限。");
        return JsonDocument.Parse(input);
    }
    internal static void WriteJson<T>(string file,T value)
    {
        // shortcut: simultaneous instances keep the last write; add merging when concurrent preference editing is required.
        var folder=Path.GetDirectoryName(Path.GetFullPath(file))!;Directory.CreateDirectory(folder);var temporary=Path.Combine(folder,".settings-"+Guid.NewGuid().ToString("N"));
        try{using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)){output.Write(JsonSerializer.SerializeToUtf8Bytes(value));output.Flush(true);}File.Move(temporary,file,true);}
        finally{if(File.Exists(temporary))File.Delete(temporary);}
    }
}

public static class MapSearchHistory
{
    public static string DefaultPath=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"PhotoTrail","Windows","map-searches-v1.json");
    public static string[] Read(string file)
    {
        if(!File.Exists(file))return [];
        using var json=SettingsPreference.ReadJson(file);
        if(json.RootElement.ValueKind!=JsonValueKind.Array)throw new InvalidDataException("搜索历史格式无效，未覆盖。");
        var history=new List<string>();
        foreach(var item in json.RootElement.EnumerateArray()){
            if(item.ValueKind!=JsonValueKind.String)throw new InvalidDataException("搜索历史包含无效词条，未覆盖。");
            var term=item.GetString()!.Trim();if(term.Length>256||term.Any(char.IsControl))throw new InvalidDataException("搜索历史词条无效，未覆盖。");
            if(term.Length>0&&!history.Contains(term,StringComparer.CurrentCultureIgnoreCase)&&history.Count<3)history.Add(term);
        }
        return history.ToArray();
    }
    public static string[] Remember(string file,string query,bool enabled)
    {
        var history=Read(file);if(!enabled)return history;var term=query.Trim();
        if(term.Length==0)return history;if(term.Length>256||term.Any(char.IsControl))throw new ArgumentException("搜索词须为1至256个可显示字符。");
        var next=new[]{term}.Concat(history.Where(s=>!StringComparer.CurrentCultureIgnoreCase.Equals(s,term))).Take(3).ToArray();SettingsPreference.WriteJson(file,next);return next;
    }
    public static void Clear(string file)=>SettingsPreference.WriteJson(file,Array.Empty<string>());
}
