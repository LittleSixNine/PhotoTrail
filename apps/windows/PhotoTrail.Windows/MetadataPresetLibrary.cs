using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PhotoTrail.Windows;
public sealed record MetadataPresetEntry(Guid Id,MetadataPreset Preset)
{
    public override string ToString()=>$"{Preset.Name} · {Preset.Operations.Count} 条操作";
}
public sealed record MetadataPresetLibrarySnapshot(IReadOnlyList<MetadataPresetEntry> Entries,string? Revision);
public static class MetadataPresetLibrary
{
    public const int MaximumBytes=1024*1024,MaximumEntries=256;
    public static string DefaultPath=>Environment.GetEnvironmentVariable("PHOTOTRAIL_METADATA_PRESETS")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"PhotoTrail","Windows","metadata-presets-v1.json");
    static string Hash(byte[] bytes)=>Convert.ToHexString(SHA256.HashData(bytes));
    // shortcut: Local mutex covers one Windows session; add cross-session coordination only when required.
    static Mutex Guard(string path)=>new(false,"Local\\PhotoTrail.MetadataPresets."+Hash(Encoding.UTF8.GetBytes(Path.GetFullPath(path).ToUpperInvariant())));
    static byte[]? ReadBytes(string path){if(!File.Exists(path))return null;using var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);if(file.Length>MaximumBytes)throw new InvalidDataException("元数据预设库超过1MiB，未覆盖原件。");using var buffer=new MemoryStream();file.CopyTo(buffer);if(buffer.Length>MaximumBytes)throw new InvalidDataException("元数据预设库超过1MiB。");return buffer.ToArray();}
    static void Members(JsonElement item,params string[] fields){if(item.ValueKind!=JsonValueKind.Object||item.EnumerateObject().Count()!=fields.Length||item.EnumerateObject().Select(p=>p.Name).Distinct(StringComparer.Ordinal).Count()!=fields.Length||item.EnumerateObject().Any(p=>!fields.Contains(p.Name)))throw new InvalidDataException("元数据预设库含未知或重复属性。");}
    static MetadataPresetEntry[] Validate(IReadOnlyList<MetadataPresetEntry> entries){
        if(entries.Count>MaximumEntries||entries.Any(e=>e is null||e.Id==Guid.Empty||e.Preset is null)||entries.Select(e=>e.Id).Distinct().Count()!=entries.Count)throw new InvalidDataException("元数据预设库条目数量或身份无效。");
        var copy=entries.Select(e=>new MetadataPresetEntry(e.Id,MetadataPreset.Create(e.Preset.Name,e.Preset.Operations))).ToArray();
        if(copy.Select(e=>e.Preset.Name).Distinct(StringComparer.Ordinal).Count()!=copy.Length)throw new InvalidDataException("元数据预设库名称碰撞（精确比较），未覆盖。");
        return copy;
    }
    public static MetadataPresetEntry[] Decode(string text){
        if(new UTF8Encoding(false,true).GetByteCount(text)>MaximumBytes)throw new InvalidDataException("元数据预设库超过1MiB。");
        using var json=JsonDocument.Parse(text.TrimStart('\ufeff'));var root=json.RootElement;Members(root,"format","version","entries");
        if(root.GetProperty("format").GetString()!="phototrail-windows-metadata-preset-library"||!root.GetProperty("version").TryGetInt32(out var version)||version!=1)throw new InvalidDataException("元数据预设库格式或版本无效。");
        var array=root.GetProperty("entries");if(array.ValueKind!=JsonValueKind.Array||array.GetArrayLength()>MaximumEntries)throw new InvalidDataException("元数据预设库最多256条。");
        var entries=new List<MetadataPresetEntry>();foreach(var item in array.EnumerateArray()){Members(item,"id","preset");if(!item.GetProperty("id").TryGetGuid(out var id))throw new InvalidDataException("元数据预设身份无效。");entries.Add(new(id,MetadataPreset.Decode(item.GetProperty("preset").GetRawText())));}return Validate(entries);
    }
    public static string Encode(IReadOnlyList<MetadataPresetEntry> entries){
        var valid=Validate(entries);var text=JsonSerializer.Serialize(new{format="phototrail-windows-metadata-preset-library",version=1,entries=valid.Select(e=>new{id=e.Id,preset=JsonSerializer.Deserialize<JsonElement>(e.Preset.Encode())})});
        if(Encoding.UTF8.GetByteCount(text)>MaximumBytes)throw new InvalidDataException("元数据预设库超过1MiB。");return text;
    }
    public static MetadataPresetLibrarySnapshot Open(string path){
        using var gate=Guard(path);try{if(!gate.WaitOne(TimeSpan.FromSeconds(10)))throw new IOException("其他实例正在写元数据预设库。");}catch(AbandonedMutexException){}
        try{var bytes=ReadBytes(path);if(bytes is null)return new(Array.AsReadOnly(Array.Empty<MetadataPresetEntry>()),null);return new(Array.AsReadOnly(Decode(new UTF8Encoding(false,true).GetString(bytes))),Hash(bytes));}finally{gate.ReleaseMutex();}
    }
    static IEnumerable<MetadataPreset> ChangedPresets(MetadataPresetLibrarySnapshot expected,IReadOnlyList<MetadataPresetEntry> entries)=>entries.Where(e=>expected.Entries.FirstOrDefault(old=>old.Id==e.Id)?.Preset.Operations.SequenceEqual(e.Preset.Operations)!=true).Select(e=>e.Preset);
    public static MetadataPresetLibrarySnapshot Save(string path,MetadataPresetLibrarySnapshot expected,IReadOnlyList<MetadataPresetEntry> entries){
        if(ChangedPresets(expected,entries).Any(p=>p.DateParameters.Any()||p.Operations.Any(op=>op.Date is not null)))throw new InvalidOperationException("新日期参数须异步共享验证后保存；旧库原件保持。");
        return SaveCore(path,expected,entries);
    }
    public static async Task<MetadataPresetLibrarySnapshot> SaveAsync(string path,MetadataPresetLibrarySnapshot expected,IReadOnlyList<MetadataPresetEntry> entries,CancellationToken token=default) {
        var frozen=Validate(entries);foreach(var preset in ChangedPresets(expected,frozen))await preset.ValidateParametersAsync(token);token.ThrowIfCancellationRequested();
        return await Task.Run(()=>{token.ThrowIfCancellationRequested();return SaveCore(path,expected,frozen,token);},token);
    }
    static MetadataPresetLibrarySnapshot SaveCore(string path,MetadataPresetLibrarySnapshot expected,IReadOnlyList<MetadataPresetEntry> entries,CancellationToken cancellation=default){
        var text=Encode(entries);using var gate=Guard(path);try{if(!gate.WaitOne(TimeSpan.FromSeconds(10)))throw new IOException("其他实例正在写元数据预设库。");}catch(AbandonedMutexException){}
        try{cancellation.ThrowIfCancellationRequested();var current=ReadBytes(path);if((current is null?null:Hash(current))!=expected.Revision)throw new IOException("另一实例或外部修改了元数据预设库；旧快照未覆盖，请明确重新读取并处理编辑。");if(current is not null)_=Decode(new UTF8Encoding(false,true).GetString(current));using var json=JsonDocument.Parse(text);cancellation.ThrowIfCancellationRequested();SettingsPreference.WriteJson(path,json.RootElement);return new(Array.AsReadOnly(Validate(entries)),Hash(Encoding.UTF8.GetBytes(text)));}finally{gate.ReleaseMutex();}
    }
    public static string Name(string name){name=name.Trim();if(name.Length is <1 or >80||name.Any(char.IsControl))throw new ArgumentException("预设名称须为1至80字且无控制字符。");_=new UTF8Encoding(false,true).GetByteCount(name);return name;}
    public static string UniqueName(string name,IEnumerable<MetadataPresetEntry> entries,bool forceNumber=false){name=Name(name);var names=entries.Select(e=>e.Preset.Name).ToHashSet(StringComparer.Ordinal);if(!forceNumber&&!names.Contains(name))return name;for(int i=2;;i++){string suffix=" "+i;int length=Math.Min(name.Length,80-suffix.Length);if(length>0&&char.IsHighSurrogate(name[length-1]))length--;string next=name[..length]+suffix;if(!names.Contains(next))return next;}}
}
