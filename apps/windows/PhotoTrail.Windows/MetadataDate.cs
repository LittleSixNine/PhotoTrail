using System.Text.RegularExpressions;
namespace PhotoTrail.Windows;

// Text extraction only; every candidate date is validated by the pinned Swift host.
internal static class MetadataDate
{
    internal static string?[] ExtractFilenames(IReadOnlyList<string> names, string pattern, string template)
    {
        if (names.Count is < 1 or > 3000 || names.Any(name => name.Length is < 1 or > 255 || name.Any(char.IsControl)) ||
            pattern.Length is < 1 or > 1024 || template.Length is < 1 or > 512 || pattern.Any(char.IsControl) || template.Any(char.IsControl))
            throw new ArgumentException("文件名解析数量/文字超出上限或含控制字符。");
        Regex expression;
        try { expression = new Regex(pattern, RegexOptions.CultureInvariant | RegexOptions.NonBacktracking, TimeSpan.FromMilliseconds(100)); }
        catch (NotSupportedException) { throw new ArgumentException("文件名正则不支持前后查找、反向引用等回溯结构；请使用普通捕获组。"); }
        foreach(Match reference in Regex.Matches(template,@"\$(\d+)",RegexOptions.CultureInvariant))if(!expression.GetGroupNumbers().Contains(int.Parse(reference.Groups[1].Value,System.Globalization.CultureInfo.InvariantCulture)))throw new ArgumentException("日期模板引用未知捕获组。");
        foreach(Match reference in Regex.Matches(template,@"\$\{([^}]+)\}",RegexOptions.CultureInvariant))if(!expression.GetGroupNames().Contains(reference.Groups[1].Value))throw new ArgumentException("日期模板引用未知命名捕获组。");
        return names.Select(name =>
        {
            var match = expression.Match(name);
            if (!match.Success) return null;
            var value = match.Result(template);
            return value;
        }).ToArray();
    }
}
