using System.IO;
using System.Text.Json;

namespace PhotoTrail.Windows;
// Deliberately bounded conversion: unsupported semantics reject the whole preset instead of dropping rules.
internal static class MacRenamePreset
{
    static readonly int[] Supported=[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,24,25,26,27,38,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,40,41,42,43,44,45,72,73,74,75,76,77,95,96,97,98];
    internal static readonly Dictionary<string,string> Lexical=new(){["Noun"]="title",["Verb"]="title",["Adjective"]="title",["Adverb"]="title",["Interjection"]="title",["Pronoun"]="lower",["Determiner"]="lower",["Preposition"]="lower",["Conjunction"]="lower",["Particle"]="lower",["Number"]="keep",["Classifier"]="keep",["Idiom"]="keep",["OtherWord"]="keep"};
    const string DatePriority="Composite:SubSecDateTimeOriginal\nComposite:DateTimeOriginal\nExifIFD:DateTimeOriginal\nXMP-exif:DateTimeOriginal\nExifIFD:CreateDate\nQuickTime:CreationDate\nQuickTime:DateTimeOriginal\nQuickTime:ContentCreateDate\nQuickTime:CreateDate\nQuickTime:MediaCreateDate\nID3:Date\nXMP-xmp:CreateDate";
    static void Shape(JsonElement value,string[] required,params string[] optional){if(value.ValueKind!=JsonValueKind.Object)throw new InvalidDataException("Mac方案对象类型无效。");var properties=value.EnumerateObject().ToArray();if(required.Any(k=>!value.TryGetProperty(k,out _))||properties.Select(p=>p.Name).Distinct().Count()!=properties.Length||properties.Any(p=>!required.Contains(p.Name)&&!optional.Contains(p.Name)))throw new InvalidDataException("Mac方案缺字段、重复或未知字段，未部分导入。");}
    internal static RenameScheme Import(JsonElement root) {
        Shape(root,["id","version","name","rules","settings"],"example");if(root.GetProperty("version").GetInt32()!=1||(!Guid.TryParse(root.GetProperty("id").GetString(),out var presetId)||presetId==Guid.Empty))throw new InvalidDataException("Mac方案版本/身份无效。");
        var elements=root.GetProperty("rules");if(elements.ValueKind!=JsonValueKind.Array||elements.GetArrayLength()>64)throw new InvalidDataException("转换最多64规则。");var ids=new HashSet<Guid>();var rules=new List<RenameRule>();
        string[] required=["id","action","enabled","part","text","replacement","anchor","position","length","occurrence","matchNumber","caseSensitive","start","counter","step","padding","alphabetStart","alphabetWidth","lexicalCases","prefix","suffix","numberOperation","numberValue","dateSource","dateFormat","timeZone","nightHour","skipMissing","fullMatch","perDirectory","filterAny","filters"];
        foreach(var element in elements.EnumerateArray()) {
            Shape(element,required,"metadataField");if(!Guid.TryParse(element.GetProperty("id").GetString(),out var id)||(id==Guid.Empty||!ids.Add(id)))throw new InvalidDataException("Mac规则身份重复/无效。");int action=element.GetProperty("action").GetInt32();if(RenameLaunchSupport.DeferredAction(action))throw new InvalidDataException(RenameLaunchSupport.DeferredMessage);if(!Supported.Contains(action))throw new InvalidDataException("Mac动作未证等价，拒绝整方案："+action);
            if(!element.GetProperty("caseSensitive").GetBoolean()&&action is >=3 and <=16 and not 5)throw new InvalidDataException("跨平台Unicode忽略大小写匹配未证等价。");
            var lexical=element.GetProperty("lexicalCases");if(lexical.ValueKind!=JsonValueKind.Object||lexical.EnumerateObject().Select(p=>p.Name).Distinct(StringComparer.Ordinal).Count()!=lexical.EnumerateObject().Count())throw new InvalidDataException("词性参数结构或重复键无效。");if(lexical.EnumerateObject().Any(p=>p.Value.ValueKind!=JsonValueKind.String||p.Value.GetString() is not("keep" or "lower" or "upper" or "title")))throw new InvalidDataException("词性参数值无效。");
            if(action is >=66 and <=71)ValidateTemplate(element.GetProperty("text").GetString()!,action,element.GetProperty("caseSensitive").GetBoolean());
            var filters=element.GetProperty("filters");if(filters.ValueKind!=JsonValueKind.Array||filters.GetArrayLength() is <1 or >32)throw new InvalidDataException("规则筛选须为1—32项。");var filterIds=new HashSet<Guid>();var conditions=new List<RenameFilterCondition>();
            foreach(var filter in filters.EnumerateArray()){Shape(filter,["id","field","comparison","value"]);if(!Guid.TryParse(filter.GetProperty("id").GetString(),out var filterId)||filterId==Guid.Empty||!filterIds.Add(filterId))throw new InvalidDataException("筛选身份重复／无效。");conditions.Add(new(filter.GetProperty("field").GetString()!,filter.GetProperty("comparison").GetString()!,filter.GetProperty("value").GetString()!){Id=filterId});}
            var converted=new Dictionary<string,object?>{{"Kind","action"},{"Action",RenameTransform.Actions.Single(p=>p.Value==action).Key},{"FilterAny",element.GetProperty("filterAny").GetBoolean()},{"Filters",conditions}};
            foreach(var property in element.EnumerateObject().Where(p=>p.Name is not("action" or "filters" or "filterAny")))converted[char.ToUpperInvariant(property.Name[0])+property.Name[1..]]=property.Value.Clone();
            RenameRule rule;try{rule=RenameTransform.Parse(JsonSerializer.Serialize(converted));}catch(ArgumentException error){throw new InvalidDataException("第"+(rules.Count+1)+"条动作"+action+"参数未能完整转换："+error.Message,error);}rules.Add(rule);
        }
        var settings=root.GetProperty("settings");Shape(settings,["conflict","sort","descending","keepFirst","pair","sourceExtensions","targetExtensions","datePriority"],"metadataSortTag","numberSuffixFormat","letterSuffixFormat","conflictDigits");
        string? Optional(string key)=>settings.TryGetProperty(key,out var value)&&value.ValueKind!=JsonValueKind.Null?value.GetString():null;
        var order=new RenameOrderSettings(settings.GetProperty("sort").GetString()!,settings.GetProperty("descending").GetBoolean(),Optional("metadataSortTag")){Pair=settings.GetProperty("pair").GetBoolean(),SourceExtensions=settings.GetProperty("sourceExtensions").GetString()!,TargetExtensions=settings.GetProperty("targetExtensions").GetString()!,DatePriority=settings.GetProperty("datePriority").GetString()!,Conflict=settings.GetProperty("conflict").GetString()!,KeepFirst=settings.GetProperty("keepFirst").GetBoolean(),NumberSuffixFormat=Optional("numberSuffixFormat")??"underscore",LetterSuffixFormat=Optional("letterSuffixFormat")??"plain",ConflictDigits=settings.TryGetProperty("conflictDigits",out var digits)&&digits.ValueKind!=JsonValueKind.Null?digits.GetInt32():3};order.Validate();
        var text=string.Join("\n",rules.Select(r=>JsonSerializer.Serialize(r)));RenamePlan.ValidateRules(text);var scheme=new RenameScheme(Guid.NewGuid(),root.GetProperty("name").GetString()!,text,order,root.TryGetProperty("example",out var example)&&example.ValueKind!=JsonValueKind.Null?example.GetString()!:"");scheme.Validate();return scheme;
    }
    // Only tokens with the same frozen lookup/date path are transferable. Local templates remain broader.
    static void ValidateTemplate(string text,int action,bool sensitive) {
        if(action is 70 or 71&&!sensitive)throw new InvalidDataException("模板锚点的Unicode忽略大小写匹配未证等价。");
        string[] photo=["FileName","FileNameWithoutExtension","FileExtension","ParentFolderName","NULL","Artist","CameraMake","CameraModel","CameraSerialNumber","ImageCaption","ImageKeywords","ImageUserComment","Lens","Aperture","ShutterSpeed","FocalLength35mm","IPTCCity","IPTCProvinceState","IPTCSubLocation","IPTCCountry","ImageWidth","ImageHeight","width","height"];
        string[] components=["Day","0Day","Month","0Month","2DigitYear","4DigitYear","Hour24","0Hour24","Hour12","0Hour12","Minute","0Minute","Second","0Second","SubSecond","0SubSecond","am_pm","AM_PM"];
        foreach(System.Text.RegularExpressions.Match match in System.Text.RegularExpressions.Regex.Matches(text,@"<([^<>]+)>")) {
            var token=match.Groups[1].Value;
            bool exact=System.Text.RegularExpressions.Regex.IsMatch(token,@"^[A-Za-z0-9][A-Za-z0-9-]*:[A-Za-z0-9][A-Za-z0-9:_-]*$");
            bool date=new[]{"ShootingDate","CreationDate","ModificationDate","ModDate"}.Any(prefix=>token.StartsWith(prefix,StringComparison.Ordinal)&&components.Contains(token[prefix.Length..]));
            if(!photo.Contains(token)&&!exact&&!date)throw new InvalidDataException("模板token未证互导等价，拒绝整方案："+token);
        }
    }
    internal static string Export(RenameScheme scheme) {
        scheme.Validate();var parsed=RenamePlan.ParseRules(scheme.Rules);RenameLaunchSupport.RequireAvailable(parsed);if(parsed.Any(r=>r.Kind!="action"||!Supported.Contains(RenameTransform.Actions[r.Action])))throw new InvalidDataException("Mac导出仅支持明确映射的Windows参数规则；旧DSL/日期/元数据/正则不自动猜转换。");
        var rules=parsed.Select(r=>{
            var properties=JsonSerializer.SerializeToElement(r).EnumerateObject().Where(p=>p.Name!="Kind").ToDictionary(p=>char.ToLowerInvariant(p.Name[0])+p.Name[1..],p=>(object?)p.Value.Clone());properties["id"]=(r.Id??Guid.NewGuid()).ToString();properties["action"]=RenameTransform.Actions[r.Action];properties["lexicalCases"]=r.LexicalCases;properties["filterAny"]=r.FilterAny;properties["filters"]=r.Filters.Select(f=>new{id=f.Id??Guid.NewGuid(),field=f.Field,comparison=f.Comparison,value=f.Value}).ToArray();return properties;
        }).ToArray();
        var settings=new{conflict=scheme.Order.Conflict,sort=scheme.Order.Sort,descending=scheme.Order.Descending,keepFirst=scheme.Order.KeepFirst,pair=scheme.Order.Pair,sourceExtensions=scheme.Order.SourceExtensions,targetExtensions=scheme.Order.TargetExtensions,datePriority=scheme.Order.DatePriority,metadataSortTag=scheme.Order.MetadataSortTag,numberSuffixFormat=scheme.Order.NumberSuffixFormat,letterSuffixFormat=scheme.Order.LetterSuffixFormat,conflictDigits=scheme.Order.ConflictDigits};
        var text=JsonSerializer.Serialize(new{id=Guid.NewGuid(),version=1,name=scheme.Name,rules,settings,example=scheme.Example});using var document=JsonDocument.Parse(text);_=Import(document.RootElement);return text;
    }
}
