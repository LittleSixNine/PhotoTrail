using System.IO;
using System.Text.Json;

namespace PhotoTrail.Windows;
// Deliberately bounded conversion: unsupported semantics reject the whole preset instead of dropping rules.
internal static class MacRenamePreset
{
    static readonly int[] Supported=[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,24,25,26,27,38,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,97];
    static readonly Dictionary<string,string> Lexical=new(){["Noun"]="title",["Verb"]="title",["Adjective"]="title",["Adverb"]="title",["Interjection"]="title",["Pronoun"]="lower",["Determiner"]="lower",["Preposition"]="lower",["Conjunction"]="lower",["Particle"]="lower",["Number"]="keep",["Classifier"]="keep",["Idiom"]="keep",["OtherWord"]="keep"};
    const string DatePriority="Composite:SubSecDateTimeOriginal\nComposite:DateTimeOriginal\nExifIFD:DateTimeOriginal\nXMP-exif:DateTimeOriginal\nExifIFD:CreateDate\nQuickTime:CreationDate\nQuickTime:DateTimeOriginal\nQuickTime:ContentCreateDate\nQuickTime:CreateDate\nQuickTime:MediaCreateDate\nID3:Date\nXMP-xmp:CreateDate";
    static void Shape(JsonElement value,string[] required,params string[] optional){if(value.ValueKind!=JsonValueKind.Object)throw new InvalidDataException("Mac方案对象类型无效。");var properties=value.EnumerateObject().ToArray();if(required.Any(k=>!value.TryGetProperty(k,out _))||properties.Select(p=>p.Name).Distinct().Count()!=properties.Length||properties.Any(p=>!required.Contains(p.Name)&&!optional.Contains(p.Name)))throw new InvalidDataException("Mac方案缺字段、重复或未知字段，未部分导入。");}
    internal static RenameScheme Import(JsonElement root) {
        Shape(root,["id","version","name","rules","settings"],"example");if(root.GetProperty("version").GetInt32()!=1||!Guid.TryParse(root.GetProperty("id").GetString(),out _))throw new InvalidDataException("Mac方案版本/身份无效。");
        var elements=root.GetProperty("rules");if(elements.ValueKind!=JsonValueKind.Array||elements.GetArrayLength()>64)throw new InvalidDataException("转换最多64规则。");var ids=new HashSet<Guid>();var rules=new List<RenameRule>();
        string[] required=["id","action","enabled","part","text","replacement","anchor","position","length","occurrence","matchNumber","caseSensitive","start","counter","step","padding","alphabetStart","alphabetWidth","lexicalCases","prefix","suffix","numberOperation","numberValue","dateSource","dateFormat","timeZone","nightHour","skipMissing","fullMatch","perDirectory","filterAny","filters"];
        foreach(var element in elements.EnumerateArray()) {
            Shape(element,required,"metadataField");if(!Guid.TryParse(element.GetProperty("id").GetString(),out var id)||!ids.Add(id))throw new InvalidDataException("Mac规则身份重复/无效。");int action=element.GetProperty("action").GetInt32();if(!Supported.Contains(action))throw new InvalidDataException("Mac动作未证等价，拒绝整方案："+action);
            if(!element.GetProperty("caseSensitive").GetBoolean()&&action<=16)throw new InvalidDataException("跨平台Unicode忽略大小写匹配未证等价。");
            var lexical=element.GetProperty("lexicalCases");Shape(lexical,Lexical.Keys.ToArray());if(lexical.EnumerateObject().Any(p=>p.Value.GetString()!=Lexical[p.Name]))throw new InvalidDataException("非默认词性转换参数不能无损转换。");
            var filters=element.GetProperty("filters");if(element.GetProperty("filterAny").GetBoolean()||filters.ValueKind!=JsonValueKind.Array||filters.GetArrayLength()!=1)throw new InvalidDataException("规则级筛选暂不转换；Windows使用任务级筛选。");var filter=filters[0];Shape(filter,["id","field","comparison","value"]);if(!Guid.TryParse(filter.GetProperty("id").GetString(),out _)||filter.GetProperty("field").GetString()!="name"||filter.GetProperty("comparison").GetString()!="contains"||filter.GetProperty("value").GetString()!="")throw new InvalidDataException("非默认筛选不能无损转换。");
            var converted=new Dictionary<string,object?>{{"Kind","action"},{"Action",RenameTransform.Actions.Single(p=>p.Value==action).Key}};
            foreach(var property in element.EnumerateObject().Where(p=>p.Name is not("id" or "action" or "lexicalCases" or "filters" or "filterAny")))converted[char.ToUpperInvariant(property.Name[0])+property.Name[1..]]=property.Value.Clone();
            var rule=RenameTransform.Parse(JsonSerializer.Serialize(converted));if(rule.DateSource!="shooting"||rule.DateFormat!="yyyyMMdd_HHmmss"||rule.TimeZone!="source"||rule.NightHour!=0)throw new InvalidDataException("本转换入口不接受非默认日期参数，即使该动作未使用。");rules.Add(rule);
        }
        var settings=root.GetProperty("settings");Shape(settings,["conflict","sort","descending","keepFirst","pair","sourceExtensions","targetExtensions","datePriority"],"metadataSortTag","numberSuffixFormat","letterSuffixFormat","conflictDigits");
        if(!settings.GetProperty("pair").GetBoolean()||settings.GetProperty("sourceExtensions").GetString()!="jpg,jpeg,heic,cr3,cr2,nef,arw,dng,raf"||settings.GetProperty("targetExtensions").GetString()!="xmp,aae,thm"||settings.GetProperty("datePriority").GetString()!=DatePriority)throw new InvalidDataException("自定义配对/日期优先级未映射，未放弃旁车保护。");
        string? Optional(string key)=>settings.TryGetProperty(key,out var value)&&value.ValueKind!=JsonValueKind.Null?value.GetString():null;
        var order=new RenameOrderSettings(settings.GetProperty("sort").GetString()!,settings.GetProperty("descending").GetBoolean(),Optional("metadataSortTag")){Conflict=settings.GetProperty("conflict").GetString()!,KeepFirst=settings.GetProperty("keepFirst").GetBoolean(),NumberSuffixFormat=Optional("numberSuffixFormat")??"underscore",LetterSuffixFormat=Optional("letterSuffixFormat")??"plain",ConflictDigits=settings.TryGetProperty("conflictDigits",out var digits)&&digits.ValueKind!=JsonValueKind.Null?digits.GetInt32():3};order.Validate();
        if(order.Sort is not("input" or "name" or "fileExtension" or "folder" or "size" or "manual"))throw new InvalidDataException("跨平台自然/元数据/日期排序未证完全等价，暂不转换。");
        var text=string.Join("\n",rules.Select(r=>JsonSerializer.Serialize(r)));RenamePlan.ValidateRules(text);var scheme=new RenameScheme(Guid.NewGuid(),root.GetProperty("name").GetString()!,text,order,root.TryGetProperty("example",out var example)&&example.ValueKind!=JsonValueKind.Null?example.GetString()!:"");scheme.Validate();return scheme;
    }
    internal static string Export(RenameScheme scheme) {
        scheme.Validate();var parsed=RenamePlan.ParseRules(scheme.Rules);if(parsed.Any(r=>r.Kind!="action"||!Supported.Contains(RenameTransform.Actions[r.Action])))throw new InvalidDataException("Mac导出仅支持明确映射的Windows参数规则；旧DSL/日期/元数据/正则不自动猜转换。");
        var rules=parsed.Select(r=>{
            var properties=JsonSerializer.SerializeToElement(r).EnumerateObject().Where(p=>p.Name!="Kind").ToDictionary(p=>char.ToLowerInvariant(p.Name[0])+p.Name[1..],p=>(object?)p.Value.Clone());properties["id"]=Guid.NewGuid().ToString();properties["action"]=RenameTransform.Actions[r.Action];properties["lexicalCases"]=Lexical;properties["filterAny"]=false;properties["filters"]=new[]{new{id=Guid.NewGuid(),field="name",comparison="contains",value=""}};return properties;
        }).ToArray();
        var settings=new{conflict=scheme.Order.Conflict,sort=scheme.Order.Sort,descending=scheme.Order.Descending,keepFirst=scheme.Order.KeepFirst,pair=true,sourceExtensions="jpg,jpeg,heic,cr3,cr2,nef,arw,dng,raf",targetExtensions="xmp,aae,thm",datePriority=DatePriority,metadataSortTag=scheme.Order.MetadataSortTag,numberSuffixFormat=scheme.Order.NumberSuffixFormat,letterSuffixFormat=scheme.Order.LetterSuffixFormat,conflictDigits=scheme.Order.ConflictDigits};
        var text=JsonSerializer.Serialize(new{id=Guid.NewGuid(),version=1,name=scheme.Name,rules,settings,example=scheme.Example});using var document=JsonDocument.Parse(text);_=Import(document.RootElement);return text;
    }
}
