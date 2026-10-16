using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Text.RegularExpressions;

namespace PhotoTrail.Windows;

public static class L10n
{
    public static readonly string[] Languages=["","zh-Hans","en","zh-Hant","ja","ko","es","pt-BR"];
    public static string[] LanguageNames=>[Text("跟随系统"),"简体中文","English","繁體中文","日本語","한국어","Español","Português (Brasil)"];
    static readonly Dictionary<string,Dictionary<string,string>> catalog=Load();
    static readonly CultureInfo systemUiCulture=CultureInfo.CurrentUICulture;
    public static string Language{get;private set;}="zh-Hans";
    static Dictionary<string,Dictionary<string,string>> Load(){using var source=typeof(L10n).Assembly.GetManifestResourceStream("PhotoTrail.Windows.Resources.LocalizedStrings.json")??throw new InvalidDataException("Localization resource missing");return JsonSerializer.Deserialize<Dictionary<string,Dictionary<string,string>>>(source)??throw new InvalidDataException("Localization resource invalid");}
    public static string Resolve(string? preferred){if(preferred is not null&&Languages.Skip(1).Contains(preferred))return preferred;var name=systemUiCulture.Name;return name.StartsWith("zh",StringComparison.OrdinalIgnoreCase)?name.Contains("TW",StringComparison.OrdinalIgnoreCase)||name.Contains("HK",StringComparison.OrdinalIgnoreCase)||name.Contains("Hant",StringComparison.OrdinalIgnoreCase)?"zh-Hant":"zh-Hans":Languages.Skip(2).FirstOrDefault(x=>name.Equals(x,StringComparison.OrdinalIgnoreCase)||name.StartsWith(x+"-",StringComparison.OrdinalIgnoreCase))??(name.StartsWith("pt",StringComparison.OrdinalIgnoreCase)?"pt-BR":"en");}
    public static void InitializeForSettings(){try{var file=Environment.GetEnvironmentVariable("PHOTOTRAIL_SETTINGS_FILE")??SettingsPreference.DefaultPath;Language=Resolve(UiPreference.Read(UiPreference.PathForSettings(file)).Language);}catch(Exception){Language=Resolve(null);}CultureInfo.CurrentUICulture=CultureInfo.GetCultureInfo(Language);CultureInfo.DefaultThreadCurrentUICulture=CultureInfo.CurrentUICulture;if(Application.Current is {} app){foreach(var pair in catalog)app.Resources[Key(pair.Key)]=Text(pair.Key);
#pragma warning disable WPF0001
        app.ThemeMode=ThemeMode.System;
#pragma warning restore WPF0001
    }}
    public static string Text(string source,string? language=null){var lang=language is null?Language:Resolve(language);return lang=="zh-Hans"?source:catalog.TryGetValue(source,out var values)&&values.TryGetValue(lang,out var result)?result:source;}
    public static string Format(string source,params object?[] values)=>string.Format(CultureInfo.CurrentCulture,Text(source),values);
    static readonly Lazy<(string Source,Regex Pattern,int[] Indices)[]> messages=new(()=>catalog.Keys.Where(k=>Regex.IsMatch(k,"[\u4e00-\u9fff]")&&Regex.IsMatch(k,@"\{\d+(?:[^{}]*)\}")).OrderByDescending(k=>Regex.Replace(k,@"\{[^{}]*\}","").Length).Select(k=>{
        var indices=new List<int>();int offset=0;var pattern=new System.Text.StringBuilder("^");foreach(Match match in Regex.Matches(k,@"\{(\d+)(?:,[^}:]+)?(?::[^}]+)?\}")){pattern.Append(Regex.Escape(k[offset..match.Index])).Append("(.*?)");indices.Add(int.Parse(match.Groups[1].Value,CultureInfo.InvariantCulture));offset=match.Index+match.Length;}pattern.Append(Regex.Escape(k[offset..])).Append('$');return(k,new Regex(pattern.ToString(),RegexOptions.CultureInvariant|RegexOptions.Singleline|RegexOptions.NonBacktracking,TimeSpan.FromMilliseconds(50)),indices.ToArray());}).ToArray());
    // Only call for generated labels/diagnostics; never for photo values, editable text or serialized data.
    public static string Message(string source){if(Language=="zh-Hans")return source;var exact=Text(source);if(exact!=source)return exact;if(source.Length>16384||!source.Any(c=>c is >= '\u4e00' and <= '\u9fff'))return source;foreach(var item in messages.Value){if(Text(item.Source)==item.Source)continue;var match=item.Pattern.Match(source);if(!match.Success)continue;var values=new object?[item.Indices.Max()+1];bool valid=true;for(int i=0;i<item.Indices.Length;i++){int at=item.Indices[i];var value=match.Groups[i+1].Value;if(values[at]is string existing&&existing!=value){valid=false;break;}values[at]=value;}if(valid)return string.Format(CultureInfo.CurrentCulture,Text(item.Source),values);}return source;}
    internal static string Key(string source)=>"L."+Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(source)))[..16];
    internal static void TranslateResources(ResourceDictionary resources){foreach(var merged in resources.MergedDictionaries)TranslateResources(merged);foreach(var key in resources.Keys.Cast<object>().ToArray())if(resources[key] is string text)resources[key]=Text(text);}
}
