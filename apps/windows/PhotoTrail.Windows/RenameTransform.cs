using System.Globalization;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace PhotoTrail.Windows;

// Named Windows actions are explicitly mapped to the pinned Mac implementation, not its preset IDs.
internal static class RenameTransform
{
    internal static readonly IReadOnlyDictionary<string,int> Actions = new Dictionary<string,int>(StringComparer.Ordinal) {
        ["add-begin"]=1,["add-end"]=2,["add-before"]=3,["add-after"]=4,["add-position"]=5,
        ["remove-begin"]=6,["remove-end"]=7,["remove-text"]=8,["replace-begin"]=9,["replace-end"]=10,["replace-text"]=11,
        ["move-front"]=12,["move-end"]=13,["move-position"]=14,["move-before"]=15,["move-after"]=16,
        ["replace-characters"]=17,["remove-characters"]=18,["keep-characters"]=19,["trim-begin"]=20,["trim-end"]=21,["remove-vowels"]=22,
        ["remove-emoji"]=23,["drop-begin"]=24,["drop-end"]=25,["remove-range"]=26,["move-range"]=27,
        ["lower"]=28,["sentence"]=29,["title"]=30,["upper"]=31,["percent-decode"]=33,["camel-expand"]=34,
        ["remove-diacritics"]=35,["mac9-name"]=36,["windows-name"]=37,["truncate"]=38,["dos83-name"]=39,
        ["date-set"]=40,["date-begin"]=41,["date-end"]=42,["date-before"]=43,["date-after"]=44,["date-position"]=45,
        ["number-set"]=46,["number-begin"]=47,["number-end"]=48,["number-before"]=49,["number-after"]=50,["number-position"]=51,["number-change"]=52,["number-remove"]=53,
        ["roman-set"]=54,["roman-begin"]=55,["roman-end"]=56,["roman-before"]=57,["roman-after"]=58,["roman-position"]=59,
        ["alphabet-set"]=60,["alphabet-begin"]=61,["alphabet-end"]=62,["alphabet-before"]=63,["alphabet-after"]=64,["alphabet-position"]=65,
        ["template-set"]=66,["template-begin"]=67,["template-end"]=68,["template-position"]=69,["template-before"]=70,["template-after"]=71,
        ["size-end"]=78,["size-begin"]=79,["size-set"]=80,["size-before"]=81,["size-after"]=82,["size-position"]=83,
        ["parent-begin"]=84,["parent-end"]=85,["parent-before"]=86,["parent-after"]=87,["parent-position"]=88,
        ["path-begin"]=89,["path-end"]=90,["path-before"]=91,["path-after"]=92,["path-position"]=93,
        ["name-list"]=94,["regex-replace"]=95,["regex-rearrange"]=96,["set"]=97,
        ["filter-following"]=98,["device-set"]=100,["device-begin"]=101,["device-end"]=102,["device-position"]=103,["device-before"]=104,["device-after"]=105,
        ["location-set"]=106,["location-begin"]=107,["location-end"]=108,["location-position"]=109,["location-before"]=110,["location-after"]=111
    };
    static readonly JsonSerializerOptions Options = new() { UnmappedMemberHandling=JsonUnmappedMemberHandling.Disallow, MaxDepth=4 };
    internal static RenameRule Parse(string text) {
        try {
            using var json=JsonDocument.Parse(text,new(){MaxDepth=4});
            if(json.RootElement.ValueKind!=JsonValueKind.Object||json.RootElement.EnumerateObject().Select(p=>p.Name).Distinct(StringComparer.Ordinal).Count()!=json.RootElement.EnumerateObject().Count())throw new ArgumentException("参数规则字段重复或类型错误。");
            var rule=JsonSerializer.Deserialize<RenameRule>(text,Options)??throw new ArgumentException("空规则。");
            if(rule.Kind!="action")throw new ArgumentException("参数规则Kind须为action；不直接读取Mac动作编号。");
            Validate(rule);return rule;
        } catch(JsonException error) {throw new ArgumentException("参数规则JSON无效："+error.Message);}
    }
    internal static bool NeedsDates(RenameRule r)=>Actions.TryGetValue(r.Action,out var n)&&(n is >=40 and <=45||n==98&&r.Filters.Any(f=>f.Field=="shootingDate")||n is >=66 and <=71&&new[]{"<ShootingDate","<CreationDate","<ModificationDate","<ModDate"}.Any(r.Text.Contains));
    internal static void Validate(RenameRule r) {
        if(new[]{r.Kind,r.Action,r.Part,r.Occurrence,r.Text,r.Replacement,r.Anchor,r.Prefix,r.Suffix,r.DateSource,r.DateFormat,r.TimeZone,r.AlphabetStart,r.NumberOperation}.Any(value=>value is null))throw new ArgumentException("规则文字字段不能为null。");
        if(!Actions.TryGetValue(r.Action,out var n))throw new ArgumentException("不支持的命名动作："+r.Action);
        if(r.Part is not("stem" or "entire" or "dottedExtension" or "extensionOnly")||r.Occurrence is not("all" or "first" or "last" or "nth")||r.MatchNumber<1||r.Position<0||r.Length<0||r.Position>4096||r.Length>4096||n==27&&r.Start<0)throw new ArgumentException("匹配域、出现次数或字形簇位置无效。");
        if(r.Padding is <0 or >32||r.AlphabetWidth is <1 or >32||r.Counter is <0 or >10||r.Counter>0&&(n is <46 or >51||r.Step<=0||r.Start<0)||r.NumberOperation is not("add" or "subtract" or "multiply" or "divide" or "set")||n==52&&r.NumberOperation=="divide"&&r.NumberValue==0)throw new ArgumentException("序列/计数器/运算参数无效；持续计数只支持向前非负数字规则。");
        if(n is >=60 and <=65)_=AlphabetIndex(r.AlphabetStart);
        foreach(var (value,multiline) in new[]{(r.Text,n==94),(r.Replacement,false),(r.Anchor,false),(r.Prefix,false),(r.Suffix,false),(r.MetadataField??"",false),(r.DateFormat,false)}) {
            if(value.Length>(multiline?16384:1024)||value.Any(c=>char.IsControl(c)&&!(multiline&&c is '\n' or '\r' or '\t')))throw new ArgumentException("参数过长或含控制字符。");
            try{_=new UTF8Encoding(false,true).GetByteCount(value);}catch(EncoderFallbackException){throw new ArgumentException("参数Unicode无效。");}
        }
        if(r.DateSource is not("shooting" or "created" or "modified" or "now")||r.TimeZone.Length is <1 or >128||r.NightHour is <0 or >23)throw new ArgumentException("日期来源、时区或夜间归日参数无效。");
        if(r.TimeZone is not("source" or "local"))try{_=TimeZoneInfo.FindSystemTimeZoneById(r.TimeZone);}catch(Exception error)when(error is TimeZoneNotFoundException or InvalidTimeZoneException){throw new ArgumentException("平台不能解析命名时区。");}
        if(r.Filters is null||r.Filters.Length is <1 or >32||r.Filters.Any(f=>f is null||f.Field is not("name" or "fileExtension" or "shootingDate" or "comment")||f.Comparison is not("contains" or "notContains" or "equals" or "notEquals" or "starts" or "ends" or "before" or "after" or "exists" or "missing")||f.Value is null||f.Value.Length>1024||f.Value.Any(char.IsControl)))throw new ArgumentException("筛选条件数量、字段、比较或参数无效。");
        foreach(var condition in r.Filters)try{_=new UTF8Encoding(false,true).GetByteCount(condition.Value);}catch(EncoderFallbackException){throw new ArgumentException("筛选参数Unicode无效。");}
        if(n is 95 or 96){_=Expression(r.Text,r.CaseSensitive);ValidateReplacement(r.Replacement);}
        if(n==94)_=ListLines(r);
        if(n is >=40 and <=45)ValidateDateFormat(r.DateFormat);
    }
    internal static (string Stem,string Extension) Split(string name) {var dot=name.LastIndexOf('.');return dot<=0?(name,""):(name[..dot],name[dot..]);}
    internal static string[] Characters(string value) {var positions=StringInfo.ParseCombiningCharacters(value);return positions.Select((p,i)=>value[p..(i+1<positions.Length?positions[i+1]:value.Length)]).ToArray();}
    static Regex Expression(string pattern,bool sensitive) {
        if(pattern.Length>1024)throw new ArgumentException("正则超过1024字符。");
        // ICU-only constructs and platform Unicode tables are not silently approximated.
        if(new[]{"\\X","\\R","\\p","\\P","\\Q","\\E","\\C","\\g","\\K","\\x{","\\u{","&&"}.Any(pattern.Contains)||Regex.IsMatch(pattern,@"\(\?(?![:=!]|<[=!])",RegexOptions.CultureInvariant,TimeSpan.FromMilliseconds(100)))throw new ArgumentException("ICU字符属性、字形簇、行分隔、特殊分组语法暂不转换；使用普通捕获组／非捕获组或前后断言。");
        try{return new(pattern,RegexOptions.CultureInvariant|(sensitive?RegexOptions.None:RegexOptions.IgnoreCase),TimeSpan.FromMilliseconds(100));}catch(ArgumentException error){throw new ArgumentException("非法正则："+error.Message);}
    }
    static void ValidateReplacement(string value) {
        for(int i=0;i<value.Length;i++)if(value[i]=='$') {
            if(i+1>=value.Length||!char.IsAsciiDigit(value[i+1]))throw new ArgumentException("捕获替换仅支持$0至$99及反斜线转义；不支持.NET特有替换变量。");
            i++;if(i+1<value.Length&&char.IsAsciiDigit(value[i+1]))i++;
        }else if(value[i]=='\\') {
            if(++i>=value.Length||!"\\$ULulE".Contains(value[i]))throw new ArgumentException("替换转义不支持。");
        }
    }
    static Match[] Matches(string name,string pattern,RenameRule r,bool regex=false) {
        if(pattern.Length==0&&!regex)return [];
        var expression=regex?Expression(pattern,r.CaseSensitive):new Regex(Regex.Escape(pattern),RegexOptions.CultureInvariant|(r.CaseSensitive?RegexOptions.None:RegexOptions.IgnoreCase),TimeSpan.FromMilliseconds(100));
        var matches=expression.Matches(name).Cast<Match>().ToArray();
        if(matches.Length>4096)throw new ArgumentException("匹配数超过4096。");
        var boundaries=StringInfo.ParseCombiningCharacters(name).Append(name.Length).ToHashSet();
        if(matches.Any(m=>m.Groups.Cast<Group>().Where(g=>g.Success).Any(g=>!boundaries.Contains(g.Index)||!boundaries.Contains(g.Index+g.Length))))throw new ArgumentException("匹配或捕获切开字形簇，拒绝生成名称。");
        return r.Occurrence switch{"first"=>matches.Take(1).ToArray(),"last"=>matches.TakeLast(1).ToArray(),"nth"=>matches.Skip(r.MatchNumber-1).Take(1).ToArray(),_=>matches};
    }
    static string Replace(string name,IEnumerable<Match> matches,Func<Match,string> value) {
        foreach(var match in matches.Reverse()){var replacement=value(match);if(name.Length-match.Length+replacement.Length>4096)throw new ArgumentException("中间名称超过4096字符。");name=name.Remove(match.Index,match.Length).Insert(match.Index,replacement);}return name;
    }
    static (string Name,string? Issue) Insert(string content,string name,int mode,RenameRule r) {
        if(mode==0)return(content,null);if(mode==1)return(content+name,null);if(mode==2)return(name+content,null);
        if(mode is 3 or 4){var matches=Matches(name,r.Anchor,r);if(matches.Length==0)return(name,"missingAnchor");return(Replace(name,matches,m=>mode==3?content+m.Value:m.Value+content),null);}
        var chars=Characters(name);if(r.Position>chars.Length)throw new ArgumentException("字形簇插入位置越界。");return(string.Concat(chars.Take(r.Position))+content+string.Concat(chars.Skip(r.Position)),null);
    }
    internal static (string Name,string? Issue,bool Skip) Apply(string name,RenameRule r,int index,Func<string,string?>? metadata,VerifiedPhotoDate? date,IReadOnlyDictionary<string,VerifiedPhotoDate?>? dates) {
        Validate(r);var parts=Split(name);var selected=r.Part switch{"entire"=>name,"dottedExtension"=>parts.Extension,"extensionOnly"=>parts.Extension.TrimStart('.'),_=>parts.Stem};
        try {
            var changed=Transform(selected,r,index,metadata,date,dates);
            if(changed.Name.Length>4096)throw new ArgumentException("中间名称过长。");
            var result=r.Part switch{"entire"=>changed.Name,"dottedExtension"=>parts.Stem+changed.Name,"extensionOnly"=>parts.Stem+(changed.Name.Length==0?"":"."+changed.Name),_=>changed.Name+parts.Extension};
            return(result,changed.Issue,r.SkipMissing&&changed.Issue is "missingDate" or "missingTag" or "listMismatch");
        }catch(RegexMatchTimeoutException){throw new ArgumentException("正则超过100ms；未生成名称。");}catch(OverflowException error){throw new ArgumentException("编号或数值运算超出64位范围。",error);}
    }
    static (string Name,string? Issue) Transform(string name,RenameRule r,int index,Func<string,string?>? metadata,VerifiedPhotoDate? date,IReadOnlyDictionary<string,VerifiedPhotoDate?>? dates) {
        int action=Actions[r.Action];string? content;int mode;
        if(action<=5)return Insert(r.Text,name,action,r);
        if(action<=11){var pattern=Regex.Escape(r.Text);var position=(action-6)%3;pattern=position==0?"^"+pattern:position==1?pattern+"$":pattern;return(Replace(name,r.Text.Length==0?[]:Matches(name,pattern,r,true),_=>action<=8?"":r.Replacement),null);}
        if(action<=16){var matches=Matches(name,r.Text,r);if(matches.Length==0)return(name,"missingAnchor");content=string.Concat(matches.Select(m=>m.Value));return Insert(content,Replace(name,matches,_=>""),new[]{1,2,5,3,4}[action-12],r);}
        var chars=Characters(name);
        if(action<=19){var search=Characters(r.Text);var replacement=Characters(r.Replacement);if(action==17&&replacement.Length!=1&&replacement.Length!=search.Length)throw new ArgumentException("字符替换须一对一或一个替换字形簇。");return(string.Concat(chars.Select(c=>{var found=Array.FindIndex(search,s=>string.Equals(s,c,r.CaseSensitive?StringComparison.Ordinal:StringComparison.OrdinalIgnoreCase));return action==19?(found>=0?c:""):found<0?c:action==18?"":replacement[replacement.Length==1?0:found];})),null);}
        switch(action) {
            case 20:return(string.Concat(chars.SkipWhile(c=>c.All(char.IsWhiteSpace))),null);
            case 21:return(string.Concat(chars.Reverse().SkipWhile(c=>c.All(char.IsWhiteSpace)).Reverse()),null);
            case 22:return(string.Concat(chars.Where(c=>c.Length!=1||!"aeiouAEIOU".Contains(c[0]))),null);
            case 23:return(string.Concat(chars.Where(c=>!c.EnumerateRunes().Any(RenameEmoji.Contains))),null);
            case 24:return(string.Concat(chars.Skip(r.Length)),null);
            case 25:return(string.Concat(chars.Take(Math.Max(0,chars.Length-r.Length))),null);
            case 26:case 27:
                if(r.Position>chars.Length||r.Length>chars.Length-r.Position)throw new ArgumentException("字形簇范围越界。");
                content=string.Concat(chars.Skip(r.Position).Take(r.Length));var remaining=chars.Take(r.Position).Concat(chars.Skip(r.Position+r.Length)).ToArray();
                if(action==26)return(string.Concat(remaining),null);if(r.Start>remaining.Length)throw new ArgumentException("移动目标字形簇位置越界。");return(string.Concat(remaining.Take((int)r.Start))+content+string.Concat(remaining.Skip((int)r.Start)),null);
            case 28:return(name.ToLowerInvariant(),null);
            case 29:return(chars.Length==0?"":chars[0].ToUpperInvariant()+string.Concat(chars.Skip(1)).ToLowerInvariant(),null);
            case 30:return(CultureInfo.InvariantCulture.TextInfo.ToTitleCase(name.ToLowerInvariant()),null);
            case 31:return(name.ToUpperInvariant(),null);
            case 33:
                if(Regex.IsMatch(name,@"%(?![0-9a-fA-F]{2})",RegexOptions.CultureInvariant,TimeSpan.FromMilliseconds(100)))return(name,null);
                // Strict UTF-8 prevents percent-decoding malformed bytes into replacement characters.
                var bytes=new List<byte>();var decoded=new StringBuilder();for(int i=0;i<name.Length;i++){if(name[i]=='%'){bytes.Add(Convert.ToByte(name.Substring(i+1,2),16));i+=2;}else{if(bytes.Count>0){decoded.Append(new UTF8Encoding(false,true).GetString(bytes.ToArray()));bytes.Clear();}decoded.Append(name[i]);}}if(bytes.Count>0)decoded.Append(new UTF8Encoding(false,true).GetString(bytes.ToArray()));return(decoded.ToString(),null);
            case 34:return(Regex.Replace(name,@"([a-z0-9])([A-Z])|([A-Z])([A-Z][a-z])",m=>m.Groups[1].Success?m.Groups[1].Value+" "+m.Groups[2].Value:m.Groups[3].Value+" "+m.Groups[4].Value,RegexOptions.CultureInvariant,TimeSpan.FromMilliseconds(100)),null);
            // Normalization is explicit only for the requested diacritic conversion; never for names or keys.
            case 35:return(string.Concat(name.Normalize(NormalizationForm.FormD).EnumerateRunes().Where(c=>Rune.GetUnicodeCategory(c)!=UnicodeCategory.NonSpacingMark).Select(c=>c.ToString())).Normalize(NormalizationForm.FormC),null);
            case 36:return(string.Concat(Characters(name.Replace(':','-').Replace('/','-')).Take(31)),null);
            case 37:
                var safe=string.Concat(name.Select(c=>char.IsControl(c)||Path.GetInvalidFileNameChars().Contains(c)?'_':c)).TrimEnd(' ','.');
                if(!RenamePlan.ValidName(safe)&&RenamePlan.ValidName("_"+safe))safe="_"+safe;return(safe,null);
            case 38:return(string.Concat(chars.Take(r.Length)),null);
            case 39:
                var p=Split(name);string Dos(string s,int length)=>string.Concat(s.ToUpperInvariant().Where(c=>char.IsAsciiLetterOrDigit(c)||"_$~!#%&-{}()@'`".Contains(c)).Take(length));var ext=Dos(p.Extension.TrimStart('.'),3);return(Dos(p.Stem,8)+(ext.Length==0?"":"."+ext),null);
            case 52:case 53:
                return(Replace(name,Matches(name,@"\d+",r,true),m=>{
                    if(action==53)return "";if(!long.TryParse(m.Value,NumberStyles.None,CultureInfo.InvariantCulture,out var number))throw new ArgumentException("已有数字不能完整解析为64位整数。");
                    var result=r.NumberOperation switch{"add"=>checked(number+r.NumberValue),"subtract"=>checked(number-r.NumberValue),"multiply"=>checked(number*r.NumberValue),"divide"=>checked(number/r.NumberValue),"set"=>r.NumberValue,_=>throw new ArgumentException("数值运算未知。")};
                    return Padded(result,Math.Max(r.Padding,Characters(m.Value).Length));
                }),null);
            case 94:
                var lines=ListLines(r);if(lines.Any(l=>l.Contains('\t'))){bool paths=Path.IsPathFullyQualified(lines[0].Split('\t')[0]);var current=metadata?.Invoke(paths?"FilePath":"FileName");if(current is null)return(name,"listMismatch");var matchesList=lines.Select(l=>l.Split('\t')).Where(row=>string.Equals(row[0],current,r.CaseSensitive?StringComparison.Ordinal:StringComparison.OrdinalIgnoreCase)).ToArray();if(matchesList.Length>1)throw new ArgumentException("命名列表重复匹配。");return matchesList.Length==1?(matchesList[0][1],null):(name,"listMismatch");}
                return index<lines.Length?(lines[index],null):(name,"listMismatch");
            case 95:case 96:
                var matches=Matches(name,r.Text,r with{Occurrence="all"},true);
                if(action==96){var match=matches.FirstOrDefault();if(match is null||r.FullMatch&&(match.Index!=0||match.Length!=name.Length))return(name,"excluded");return(Replacement(r.Replacement,match),null);}
                return(Replace(name,matches,m=>Replacement(r.Replacement,m)),null);
            case 97:return(r.Text,null);
        }
        if(action is >=46 and <=65){var initial=action>=60?AlphabetIndex(r.AlphabetStart):r.Start;var number=checked(initial+checked(r.Step*index));content=action>=60?Alphabet(number):action>=54?Roman(number):Padded(number,r.Padding);if(action>=60){content=new string('A',Math.Max(0,r.AlphabetWidth-content.Length))+content;if(r.AlphabetStart==r.AlphabetStart.ToLowerInvariant())content=content.ToLowerInvariant();}else if(action>=54&&!r.CaseSensitive)content=content.ToLowerInvariant();content=r.Prefix+content+r.Suffix;mode=action>=60?action-60:action>=54?action-54:action-46;}
        else if(action is >=40 and <=45){content=FormatDate(r,metadata,date,dates);mode=action-40;if(content is null)return(name,"missingDate");}
        else if(action is >=66 and <=71){content=Template(r.Text,r,metadata,date,dates);mode=new[]{0,1,2,5,3,4}[action-66];if(content is null)return(name,"missingTag");}
        else if(action is >=78 and <=83){var width=metadata?.Invoke("ImageWidth");var height=metadata?.Invoke("ImageHeight");if(width is null||height is null)return(name,"missingTag");if(!int.TryParse(width,NumberStyles.None,CultureInfo.InvariantCulture,out var w)||!int.TryParse(height,NumberStyles.None,CultureInfo.InvariantCulture,out var h)||w<1||h<1)throw new ArgumentException("尺寸快照不是合法正整数。");content=r.Prefix+width+(r.Text.Length==0?"x":r.Text)+height+r.Suffix;mode=new[]{2,1,0,3,4,5}[action-78];}
        else if(action is >=84 and <=93){content=metadata?.Invoke(action<=88?"ParentFolderName":"FilePath");if(content is null)return(name,"missingTag");if(action>=89){var dir=Path.GetDirectoryName(content)!;var components=dir[Path.GetPathRoot(dir)!.Length..].Split(Path.DirectorySeparatorChar,StringSplitOptions.RemoveEmptyEntries).Reverse().ToArray();if(r.Position>=components.Length||r.Length==0||r.SkipMissing&&components.Length-r.Position<r.Length)return(name,"missingTag");content=string.Join(r.Text.Length==0?"_":r.Text,components.Skip(r.Position).Take(r.Length).Reverse());}content=r.Prefix+content+r.Suffix;mode=action<=88?action-83:action-88;}
        else{content=metadata?.Invoke(r.MetadataField??(action<106?"CameraModel":"IPTCCity"));if(content is null)return(name,"missingTag");content=r.Prefix+content+r.Suffix;mode=new[]{0,1,2,5,3,4}[(action-100)%6];}
        return Insert(content,name,mode,r);
    }
    internal static string Padded(long number,int width){var value=number.ToString(CultureInfo.InvariantCulture);var digits=value.TrimStart('-');return(number<0?"-":"")+new string('0',Math.Max(0,width-digits.Length))+digits;}
    internal static long AlphabetIndex(string value){if(value.Length is <1 or >7||value.Any(c=>!char.IsAsciiLetter(c)))throw new ArgumentException("字母起点须A至Z组合且在1至十亿范围。");long result=0;foreach(var c in value.ToUpperInvariant())result=checked(result*26+c-'A'+1);if(result>1_000_000_000)throw new ArgumentException("字母编号超过十亿。");return result;}
    internal static string Alphabet(long number){if(number is <1 or >1_000_000_000)throw new ArgumentException("字母编号须1至十亿。");var result="";while(number>0){number--;result=(char)('A'+number%26)+result;number/=26;}return result;}
    internal static string Roman(long number){if(number is <1 or >3999)throw new ArgumentException("罗马编号须1至3999。");var result=new StringBuilder();foreach(var (value,letters) in new[]{(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),(90,"XC"),(50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")})while(number>=value){result.Append(letters);number-=value;}return result.ToString();}
    static string[] ListLines(RenameRule r){var lines=r.Text.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries);if(lines.Length>1000)throw new ArgumentException("命名列表超过1000项。");if(lines.Any(l=>l.Contains('\t'))){if(lines.Any(l=>l.Split('\t').Length!=2))throw new ArgumentException("列表映射必须全部两列。");bool paths=Path.IsPathFullyQualified(lines[0].Split('\t')[0]);if(lines.Any(l=>Path.IsPathFullyQualified(l.Split('\t')[0])!=paths)||lines.Select(l=>l.Split('\t')[0]).Distinct(r.CaseSensitive?StringComparer.Ordinal:StringComparer.OrdinalIgnoreCase).Count()!=lines.Length)throw new ArgumentException("命名列表混用路径/文件名或重复来源。");}return lines;}
    static string Replacement(string template,Match match) {
        var output=new StringBuilder();char run='\0',next='\0';
        void Append(string text){if(run=='U')text=text.ToUpperInvariant();if(run=='L')text=text.ToLowerInvariant();if(text.Length>0&&next!='\0'){var chars=Characters(text);text=(next=='u'?chars[0].ToUpperInvariant():chars[0].ToLowerInvariant())+string.Concat(chars.Skip(1));next='\0';}output.Append(text);}
        for(int i=0;i<template.Length;i++) {
            if(template[i]=='\\'){var command=template[++i];if(command is 'U' or 'L')run=command;else if(command is 'u' or 'l')next=command;else if(command=='E'){run='\0';next='\0';}else Append(command.ToString());}
            else if(template[i]=='$'){int start=++i;while(i+1<template.Length&&i-start<1&&char.IsAsciiDigit(template[i+1]))i++;int group=int.Parse(template[start..(i+1)],CultureInfo.InvariantCulture);if(group>=match.Groups.Count)throw new ArgumentException("替换引用不存在的捕获组。");Append(match.Groups[group].Value);}
            else Append(template[i].ToString());
        }return output.ToString();
    }
    static readonly string[] DateTokens=["yyyy","yy","MM","M","dd","d","HH","H","hh","h","mm","m","ss","s","SSS","SS","a","XXX"];
    static IEnumerable<(string Token,bool Literal)> FormatTokens(string format) {
        for(int i=0;i<format.Length;){if(format[i]=='\''){int end=format.IndexOf('\'',i+1);if(end<0)throw new ArgumentException("日期格式引号未闭合。");yield return(format[(i+1)..end],true);i=end+1;continue;}var token=DateTokens.FirstOrDefault(t=>format.AsSpan(i).StartsWith(t,StringComparison.Ordinal));if(token is not null){yield return(token,false);i+=token.Length;}else{if(char.IsLetter(format[i]))throw new ArgumentException("日期格式仅支持已验证墙钟数字字段、a、XXX及引号字面文字。");yield return(format[i++].ToString(),true);}}
    }
    static void ValidateDateFormat(string format){if(format.Length==0)throw new ArgumentException("日期格式为空。");_=FormatTokens(format).ToArray();}
    internal static string DateKey(string raw,RenameRule r)=>raw+"|zone="+r.TimeZone+"|night="+r.NightHour.ToString(CultureInfo.InvariantCulture);
    internal static async Task<IReadOnlyDictionary<string,VerifiedPhotoDate?>> PrepareDatesAsync(IEnumerable<string> texts,IReadOnlyList<RenameRule> rules,CancellationToken token) {
        var dates=(await VerifiedPhotoDate.InspectAsync(texts,token)).ToDictionary(p=>p.Key,p=>p.Value,StringComparer.Ordinal);
        var variants=rules.Where(r=>r.Enabled&&r.Kind=="action"&&NeedsDates(r)&&(r.TimeZone!="source"||r.NightHour!=0)).DistinctBy(r=>(r.TimeZone,r.NightHour)).ToArray();
        foreach(var variant in variants) {
            Validate(variant);var adapted=new Dictionary<string,string>();var shifted=new Dictionary<string,string>();
            foreach(var (raw,proof) in dates.Where(p=>!p.Key.Contains("|zone=",StringComparison.Ordinal)).ToArray()) {
                token.ThrowIfCancellationRequested();if(proof is null)continue;var text=proof.Text;
                if(variant.TimeZone!="source"&&proof.Offset.Length>0) {
                    // Native timezone formatting is bounded to modern, representable instants; the shared core proves the date first.
                    if(proof.InstantLimitation is not null||string.CompareOrdinal(text[..10],"1582:10:15")<0)continue;
                    var zone=variant.TimeZone=="local"?TimeZoneInfo.Local:TimeZoneInfo.FindSystemTimeZoneById(variant.TimeZone);
                    var instant=proof.Instant()!.Value;var wall=TimeZoneInfo.ConvertTime(instant,zone);if(wall.UtcTicks!=instant.UtcTicks)continue;var offset=wall.Offset;
                    text=wall.ToString("yyyy:MM:dd HH:mm:ss",CultureInfo.InvariantCulture)+proof.Fraction+(offset==TimeSpan.Zero?"Z":(offset<TimeSpan.Zero?"-":"+")+offset.Duration().ToString(@"hh\:mm",CultureInfo.InvariantCulture));
                }
                adapted[DateKey(raw,variant)]=text;
                if(variant.NightHour>0&&int.Parse(text[11..13],CultureInfo.InvariantCulture)<variant.NightHour)shifted[DateKey(raw,variant)]=text;
            }
            if(shifted.Count>0) {
                var adapter=new DateAdapter(Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe"),DatePagePreview.Source);
                var keys=shifted.Keys.ToArray();var results=await adapter.ComputeAsync(keys.Select((key,i)=>new DateJob(new WireItem(i.ToString(CultureInfo.InvariantCulture),"offset",shifted[key],Days:-1))).ToArray(),0,()=>0,token);
                for(int i=0;i<keys.Length;i++){if(results[i].Error is not null)adapted.Remove(keys[i]);else adapted[keys[i]]=results[i].Values!.Single();}
            }
            var verified=await VerifiedPhotoDate.InspectAsync(adapted.Values,token);foreach(var (key,text) in adapted)dates[key]=verified.GetValueOrDefault(text);
        }
        return dates;
    }
    internal static bool MatchesFilter(string original,RenameRule rule,Func<string,string?>? metadata,VerifiedPhotoDate? date,IReadOnlyDictionary<string,VerifiedPhotoDate?>? dates) {
        Validate(rule);
        string Key(string text)=>rule.CaseSensitive?text:text.Normalize(NormalizationForm.FormC).ToLowerInvariant();
        bool Match(RenameFilterCondition condition) {
            string? value=condition.Field switch{"name"=>original,"fileExtension"=>Split(original).Extension.TrimStart('.'),"comment"=>metadata?.Invoke("ImageUserComment"),_=>FormatDate(rule with{DateSource="shooting",DateFormat="yyyy-MM-dd HH:mm:ss"},metadata,date,dates)};
            if(condition.Comparison=="exists")return !string.IsNullOrEmpty(value);if(condition.Comparison=="missing")return string.IsNullOrEmpty(value);if(value is null)return false;
            var actual=Key(value);var expected=Key(condition.Value);return condition.Comparison switch{"contains"=>actual.Contains(expected,StringComparison.Ordinal),"notContains"=>!actual.Contains(expected,StringComparison.Ordinal),"equals"=>actual==expected,"notEquals"=>actual!=expected,"starts"=>actual.StartsWith(expected,StringComparison.Ordinal),"ends"=>actual.EndsWith(expected,StringComparison.Ordinal),"before"=>string.CompareOrdinal(actual,expected)<0,"after"=>string.CompareOrdinal(actual,expected)>0,_=>false};
        }
        return rule.FilterAny?rule.Filters.Any(Match):rule.Filters.All(Match);
    }
    static string? FormatDate(RenameRule r,Func<string,string?>? metadata,VerifiedPhotoDate? date,IReadOnlyDictionary<string,VerifiedPhotoDate?>? dates) {
        var raw=metadata?.Invoke(r.DateSource=="created"?"File:FileCreateDate":r.DateSource=="modified"?"File:FileModifyDate":r.DateSource=="now"?"PhotoTrail:RenameReferenceDate":"captured");if(raw is null)return null;raw=RenameInput.BridgeDate(raw);
        var variant=r.TimeZone!="source"||r.NightHour!=0;
        var verified=dates?.GetValueOrDefault(variant?DateKey(raw,r):raw)??(!variant&&date?.Text==raw?date:null);if(verified is null)return null;
        ValidateDateFormat(r.DateFormat);var text=verified.Text;var hour=int.Parse(text[11..13],CultureInfo.InvariantCulture);
        string Trim(string value)=>int.Parse(value,CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture);
        return string.Concat(FormatTokens(r.DateFormat).Select(t=>t.Literal?t.Token:t.Token switch{
            "yyyy"=>text[..4],"yy"=>text[2..4],"MM"=>text[5..7],"M"=>Trim(text[5..7]),"dd"=>text[8..10],"d"=>Trim(text[8..10]),"HH"=>text[11..13],"H"=>Trim(text[11..13]),"hh"=>(hour%12==0?12:hour%12).ToString("D2",CultureInfo.InvariantCulture),"h"=>(hour%12==0?12:hour%12).ToString(CultureInfo.InvariantCulture),"mm"=>text[14..16],"m"=>Trim(text[14..16]),"ss"=>text[17..19],"s"=>Trim(text[17..19]),"a"=>hour<12?"AM":"PM","SS" or "SSS"=>(verified.Fraction.TrimStart('.')+"000")[..t.Token.Length],"XXX"=>verified.Offset.Length==0?throw new ArgumentException("源偏移缺失，不能格式化XXX。"):verified.Offset,_=>throw new ArgumentException("日期格式未映射。")}));
    }
    static string? Template(string template,RenameRule r,Func<string,string?>? metadata,VerifiedPhotoDate? date,IReadOnlyDictionary<string,VerifiedPhotoDate?>? dates) {
        bool missing=false;var result=Regex.Replace(template,@"<([^<>]+)>",m=>{
            var token=m.Groups[1].Value;string? value=null;
            var components=new Dictionary<string,string>{{"Day","d"},{"0Day","dd"},{"Month","M"},{"0Month","MM"},{"2DigitYear","yy"},{"4DigitYear","yyyy"},{"Hour24","H"},{"0Hour24","HH"},{"Hour12","h"},{"0Hour12","hh"},{"Minute","m"},{"0Minute","mm"},{"Second","s"},{"0Second","ss"},{"SubSecond","SS"},{"0SubSecond","SSS"},{"am_pm","a"},{"AM_PM","a"}};
            foreach(var (prefix,source) in new[]{("ShootingDate","shooting"),("CreationDate","created"),("ModificationDate","modified"),("ModDate","modified")})if(token.StartsWith(prefix,StringComparison.Ordinal)&&components.TryGetValue(token[prefix.Length..],out var format)){value=FormatDate(r with{DateSource=source,DateFormat=format},metadata,date,dates);if(token.EndsWith("am_pm",StringComparison.Ordinal))value=value?.ToLowerInvariant();}
            value??=metadata?.Invoke(token);if(value is null){missing=true;return "";}return value;
        },RegexOptions.CultureInvariant,TimeSpan.FromMilliseconds(100));return missing?null:result;
    }
}
