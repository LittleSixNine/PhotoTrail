using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PhotoTrail.Windows;
public sealed record RenameScheme(Guid Id,string Name,string Rules,RenameOrderSettings Order,string Example)
{
    public override string ToString()=>Name;
    internal void Validate() {
        if(Id==Guid.Empty)throw new ArgumentException("方案身份无效。");
        RenameSchemeLibrary.Label(Name,false,100);RenameSchemeLibrary.Label(Example,true,255);
        if(Order is null)throw new ArgumentException("方案排序缺失。");Order.Validate();RenamePlan.ValidateRules(Rules);
    }
}
public sealed record RenameSchemeState(string Format,int Version,bool Initialized,Guid? LastId,RenameScheme[] Schemes)
{
    internal void Validate() {
        if(Format!="phototrail-windows-rename-library"||Version is not(1 or 2)||!Initialized||Schemes is null||Schemes.Length>256||Schemes.Any(s=>s is null)||Schemes.Select(s=>s.Id).Distinct().Count()!=Schemes.Length||Schemes.Select(s=>s.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=Schemes.Length||LastId is {} id&&!Schemes.Any(s=>s.Id==id))throw new InvalidDataException("方案库结构、版本或身份无效；未覆盖原记录。");
        foreach(var scheme in Schemes)scheme.Validate();
    }
}
public sealed record RenameSchemeSnapshot(RenameSchemeState State,string Revision);
public static class RenameSchemeLibrary
{
    public const int MaximumBytes=1024*1024;
    public static string DefaultPath=>Environment.GetEnvironmentVariable("PHOTOTRAIL_RENAME_SCHEMES")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"PhotoTrail","Windows","rename-schemes-v1.json");
    static readonly JsonSerializerOptions Options=new(){PropertyNamingPolicy=JsonNamingPolicy.CamelCase,UnmappedMemberHandling=JsonUnmappedMemberHandling.Disallow,RespectRequiredConstructorParameters=true,RespectNullableAnnotations=true};
    internal static void Label(string value,bool empty,int maximum) {
        if(value is null||value.Length>maximum||!empty&&string.IsNullOrWhiteSpace(value)||value.Any(char.IsControl))throw new ArgumentException("方案名称／示例为空、超长或含控制字符。");
        _=new UTF8Encoding(false,true).GetByteCount(value);
    }
    static void UniqueProperties(JsonElement item) {
        if(item.ValueKind==JsonValueKind.Object){var keys=new HashSet<string>(StringComparer.Ordinal);foreach(var property in item.EnumerateObject()){if(!keys.Add(property.Name))throw new InvalidDataException("JSON含重复属性。");UniqueProperties(property.Value);}}
        else if(item.ValueKind==JsonValueKind.Array)foreach(var value in item.EnumerateArray())UniqueProperties(value);
    }
    internal static T Decode<T>(string text) {
        if(new UTF8Encoding(false,true).GetByteCount(text)>MaximumBytes)throw new InvalidDataException("方案内容超过1MiB。");
        using var json=JsonDocument.Parse(text.TrimStart('﻿'));UniqueProperties(json.RootElement);
        return JsonSerializer.Deserialize<T>(json.RootElement,Options)??throw new InvalidDataException("方案内容为空。");
    }
    static string Hash(byte[] data)=>Convert.ToHexString(SHA256.HashData(data));
    static string? Revision(string path){if(!File.Exists(path))return null;if(new FileInfo(path).Length>MaximumBytes)throw new InvalidDataException("方案库超过1MiB，未覆盖。");return Hash(File.ReadAllBytes(path));}
    // shortcut: Local mutex covers one Windows session; use cross-session coordination if that scope is required.
    static Mutex Guard(string path)=>new(false,"Local\\PhotoTrail.RenameSchemes."+Hash(Encoding.UTF8.GetBytes(Path.GetFullPath(path).ToUpperInvariant())));
    public static RenameSchemeSnapshot Open(string path) {
        using var gate=Guard(path);try{if(!gate.WaitOne(TimeSpan.FromSeconds(10)))throw new IOException("其他实例正在保存方案。");}catch(AbandonedMutexException){}
        try {
            if(!File.Exists(path)){
                var defaults=Defaults();var state=new RenameSchemeState("phototrail-windows-rename-library",1,true,defaults[0].Id,defaults);return SaveLocked(path,null,state);
            }
            using var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);if(file.Length>MaximumBytes)throw new InvalidDataException("方案库超过1MiB，未覆盖。");
            using var reader=new StreamReader(file,new UTF8Encoding(false,true),false);var text=reader.ReadToEnd();var loaded=Decode<RenameSchemeState>(text);loaded.Validate();return new(loaded,Revision(path)!);
        }finally{gate.ReleaseMutex();}
    }
    static RenameSchemeSnapshot SaveLocked(string path,string? expected,RenameSchemeState state) {
        state=state with{Version=2};state.Validate();var bytes=JsonSerializer.SerializeToUtf8Bytes(state,Options);if(bytes.Length>MaximumBytes)throw new InvalidDataException("方案库超过1MiB。");
        if(Revision(path)!=expected)throw new IOException("另一实例或外部修改了方案库；保留当前编辑，请重新打开后处理冲突。");
        SettingsPreference.WriteJson(path,JsonSerializer.SerializeToElement(state,Options));return new(state,Hash(bytes));
    }
    public static RenameSchemeSnapshot Save(string path,RenameSchemeSnapshot expected,RenameSchemeState state) {
        foreach(var scheme in state.Schemes.Where(s=>!expected.State.Schemes.Contains(s)))RenameLaunchSupport.RequireAvailable(RenamePlan.ParseRules(scheme.Rules));
        using var gate=Guard(path);try{if(!gate.WaitOne(TimeSpan.FromSeconds(10)))throw new IOException("其他实例正在保存方案。");}catch(AbandonedMutexException){}
        try{return SaveLocked(path,expected.Revision,state);}finally{gate.ReleaseMutex();}
    }
    public static string UniqueName(string name,IEnumerable<RenameScheme> schemes,Guid? excluding=null) {
        Label(name,false,100);name=name.Trim();var names=schemes.Where(s=>s.Id!=excluding).Select(s=>s.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);var next=name;int suffix=2;
        while(names.Contains(next)){var ending=" ("+(suffix++)+")";next=name[..Math.Min(name.Length,100-ending.Length)]+ending;}return next;
    }
    public static string Export(RenameScheme scheme) {scheme.Validate();RenameLaunchSupport.RequireAvailable(RenamePlan.ParseRules(scheme.Rules));return JsonSerializer.Serialize(new SchemeFile("phototrail-windows-rename-scheme",3,scheme),Options);}
    sealed record SchemeFile(string Format,int Version,RenameScheme Scheme);
    public static RenameScheme Import(string text,string legacyName) {
        if(new UTF8Encoding(false,true).GetByteCount(text)>MaximumBytes)throw new InvalidDataException("方案超过1MiB。");
        using var json=JsonDocument.Parse(text.TrimStart('﻿'));UniqueProperties(json.RootElement);
        if(json.RootElement.TryGetProperty("settings",out _)&&json.RootElement.TryGetProperty("rules",out var macRules)&&macRules.ValueKind==JsonValueKind.Array){try{return MacRenamePreset.Import(json.RootElement);}catch(Exception error)when(error is JsonException or InvalidOperationException or KeyNotFoundException or ArgumentException){throw new InvalidDataException("Mac方案无法完整转换；当前方案和原文件保持。",error);}}
        RenameScheme result;
        if(json.RootElement.TryGetProperty("format",out _)) {
            var file=Decode<SchemeFile>(text);if(file.Format!="phototrail-windows-rename-scheme"||file.Version is not(2 or 3))throw new InvalidDataException("不支持此方案格式；Mac与Windows不能直接互导。");result=file.Scheme;
            if(file.Version==2&&(RenamePlan.RequiresV3(RenamePlan.ParseRules(result.Rules))||json.RootElement.GetProperty("scheme").GetProperty("order").EnumerateObject().Any(p=>p.Name is not("sort" or "descending" or "metadataSortTag"))))throw new InvalidDataException("高级参数须Windows方案v3，不按旧版本猜测。");
        }else {
            RenameRulesPreset preset;
            try{preset=RenameRulesPreset.Decode(text);}catch(Exception error)when(error is ArgumentException or JsonException or InvalidDataException){throw new InvalidDataException("不支持此JSON方案格式；仅支持Windows方案或旧Windows规则，Mac方案不能直接互导。",error);}
            result=new(Guid.NewGuid(),legacyName,preset.Rules,preset.Order??new(preset.SortByName?"name":"input"),"");
        }
        result.Validate();RenameLaunchSupport.RequireAvailable(RenamePlan.ParseRules(result.Rules));return result with{Id=Guid.NewGuid()};
    }
    public static RenameScheme[] Defaults() {
        RenameScheme S(string name,string rules,string example)=>new(Guid.NewGuid(),name,rules,new RenameOrderSettings("name"){Conflict="numbers"},example);
        return [S("城市＋拍摄时间","date-set\ncity-prefix|_","上海市_20261006_171649.jpg"),S("数字编号＋原名","sequence-prefix|1|1|4|_","0001_DSC_1234.jpg"),S("拍摄时间＋设备型号","date-set\nmodel-suffix|_","20261006_171649_NIKON D750.jpg"),S("拍摄时间＋原名","date-prefix|_","20261006_171649_DSC_1234.jpg"),S("自定义前缀＋编号","set|请自定义文字_\nsequence|1|1|4","请自定义文字_0001.jpg")];
    }
}
