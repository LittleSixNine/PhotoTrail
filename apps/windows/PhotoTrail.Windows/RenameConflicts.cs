using System.IO;

namespace PhotoTrail.Windows;
internal static class RenameConflicts
{
    internal static RenameFile[] Resolve(IReadOnlyList<RenameFile> files,IReadOnlyDictionary<string,string> groups,RenameOrderSettings settings)
    {
        settings.Validate();var occupied=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var directory in files.Select(f=>Path.GetDirectoryName(f.Source)!).Distinct(StringComparer.OrdinalIgnoreCase)){
            int count=0;foreach(var path in Directory.EnumerateFileSystemEntries(directory)){if(++count>100000)throw new IOException("目录冲突扫描超过100000项，未冻结。");occupied.Add(path);}
        }
        foreach(var file in files.Where(f=>f.Source!=f.Target))occupied.Remove(file.Source);
        var result=new List<RenameFile>();
        foreach(var group in files.GroupBy(f=>groups[f.Source])) {
            var members=group.ToArray();if(members.All(f=>f.Source==f.Target)){result.AddRange(members);continue;}
            int suffix=settings.KeepFirst?0:1;
            while(true){
                var value=settings.Conflict=="letters"&&suffix>0?RenameTransform.Alphabet(suffix):RenameTransform.Padded(suffix,settings.ConflictDigits);
                string format=settings.Conflict=="letters"?settings.LetterSuffixFormat:settings.NumberSuffixFormat;
                string tail=suffix==0?"":format switch{"underscore"=>"_"+value,"dash"=>"-"+value,"parentheses"=>"("+value+")",_=>value};
                var proposed=members.Select(f=>{var parts=RenameTransform.Split(Path.GetFileName(f.Target));var name=parts.Stem+tail+parts.Extension;return f with{Target=Path.Combine(Path.GetDirectoryName(f.Target)!,name),Steps=f.Steps+(tail.Length==0?"":" → 冲突后缀: "+name)};}).ToArray();
                if(proposed.Any(f=>!RenamePlan.ValidName(f.NewName)))throw new ArgumentException("碰撞后缀后的Windows名称无效或过长。");
                if(proposed.Select(f=>f.Target).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=proposed.Length)throw new IOException("配对成员的目标扩展名重叠，后缀不能解除冲突。");
                if(proposed.All(f=>!occupied.Contains(f.Target))){foreach(var file in proposed)occupied.Add(file.Target);result.AddRange(proposed);break;}
                if(settings.Conflict=="stop"||suffix>=100000)throw new IOException("目标冲突或后缀尝试超过100000次，未冻结且不覆盖。");suffix++;
            }
        }
        return result.ToArray();
    }
}
