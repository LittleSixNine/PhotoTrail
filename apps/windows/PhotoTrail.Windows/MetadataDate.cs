using System.Globalization;
using System.Text.RegularExpressions;

namespace PhotoTrail.Windows;

public sealed record MetadataDate(DateTime WallTime, string Fraction, string Offset)
{
    public static MetadataDate Parse(string text)
    {
        var match = Regex.Match(text, @"\A([0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})?\z", RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));
        if (!match.Success || !DateTime.TryParseExact(match.Groups[1].Value, "yyyy:MM:dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
            throw new ArgumentException("拍摄时间格式无效；使用yyyy:MM:dd HH:mm:ss，可附小数秒及Z或±hh:mm。");
        var offset = match.Groups[3].Value;
        if (offset.Length > 1)
        {
            var hours = int.Parse(offset.AsSpan(1, 2), CultureInfo.InvariantCulture); var minutes = int.Parse(offset.AsSpan(4, 2), CultureInfo.InvariantCulture);
            if (hours > 14 || minutes > 59 || (hours == 14 && minutes != 0)) throw new ArgumentException("时间偏移须在±14:00以内。");
        }
        // Missing timezone remains wall-clock time; fractional digits are preserved without rounding.
        return new(DateTime.SpecifyKind(date, DateTimeKind.Unspecified), match.Groups[2].Value, offset);
    }
    public DateTimeOffset? Instant()
    {
        if (Offset.Length == 0 || (Fraction.Length > 8 && Fraction[8..].Any(c => c != '0'))) return null;
        try
        {
            var ticks = Fraction.Length == 0 ? 0 : long.Parse(Fraction[1..].PadRight(7, '0')[..7], CultureInfo.InvariantCulture);
            var offset = Offset == "Z" ? TimeSpan.Zero : TimeSpan.ParseExact(Offset[1..], @"hh\:mm", CultureInfo.InvariantCulture) * (Offset[0] == '-' ? -1 : 1);
            return new DateTimeOffset(WallTime.AddTicks(ticks), offset);
        }
        catch (ArgumentException) { return null; }
    }
    public string Text => WallTime.ToString("yyyy:MM:dd HH:mm:ss", CultureInfo.InvariantCulture) + Fraction + Offset;
    public MetadataDate Shift(int years, int months, int days, int hours, int minutes, long seconds)
    {
        if (years is < -9999 or > 9999 || months is < -120000 or > 120000 || days is < -3660000 or > 3660000 ||
            hours is < -87840000 or > 87840000 || minutes is < -int.MaxValue or > int.MaxValue || seconds is < -316224000000 or > 316224000000)
            throw new ArgumentException("时间调整超出支持范围。");
        try
        {
            var date = WallTime.AddYears(years);
            if (date.Day != WallTime.Day) throw new ArgumentException("调整年份会改变原日期，例如闰年2月29日；请明确指定合法日期。");
            var next = date.AddMonths(months);
            if (next.Day != date.Day) throw new ArgumentException("调整月份会改变原日期，例如31日落入小月；请明确指定合法日期。");
            date = next.AddDays(days).AddHours(hours).AddMinutes(minutes).AddTicks(checked(seconds * TimeSpan.TicksPerSecond));
            return this with { WallTime = date };
        }
        catch (Exception error) when (error is ArgumentOutOfRangeException or OverflowException) { throw new ArgumentException("调整后日期超出0001至9999年范围。"); }
    }
    public MetadataDate Replace(int? year = null, int? month = null, int? day = null, int? hour = null, int? minute = null, int? second = null)
    {
        if (year is null && month is null && day is null && hour is null && minute is null && second is null)
            throw new ArgumentException("请至少指定一个日期组件；留空保留原值。");
        try
        {
            return this with { WallTime = new DateTime(year ?? WallTime.Year, month ?? WallTime.Month, day ?? WallTime.Day,
                hour ?? WallTime.Hour, minute ?? WallTime.Minute, second ?? WallTime.Second, DateTimeKind.Unspecified) };
        }
        catch (ArgumentOutOfRangeException) { throw new ArgumentException("替换后日期无效；不会自动截断或调整其他组件。"); }
    }
    public static string[] Distribute(string start, string end, int count)
    {
        if (count is < 1 or > 3000) throw new ArgumentException("分布数量须为1至3000。");
        var first = Parse(start); var last = Parse(end);
        if (first.Offset != last.Offset || first.Fraction != last.Fraction || last.WallTime < first.WallTime)
            throw new ArgumentException("分布起止须使用相同小数秒和固定时区，终点不能早于起点。");
        if (count == 1) return [first.Text];
        var seconds = (last.WallTime.Ticks - first.WallTime.Ticks) / TimeSpan.TicksPerSecond;
        // Integer nearest-second rounding keeps endpoints and suffixes exact, including nine-digit fractions.
        return Enumerable.Range(0, count).Select(index => first.Shift(0,0,0,0,0,
            checked(seconds * index + (count - 1) / 2) / (count - 1)).Text).ToArray();
    }
    public static string?[] FromFilenames(IReadOnlyList<string> names, string pattern, string template)
    {
        return ExtractFilenames(names,pattern,template).Select(value=> {
            if(value is null)return null;
            try{return Parse(value).Text;}catch(ArgumentException){return null;}
        }).ToArray();
    }
    internal static string?[] ExtractFilenames(IReadOnlyList<string> names, string pattern, string template)
    {
        if (names.Count is < 1 or > 3000 || names.Any(name => name.Length is < 1 or > 255 || name.Any(char.IsControl)) ||
            pattern.Length is < 1 or > 1024 || template.Length is < 1 or > 512 || pattern.Any(char.IsControl) || template.Any(char.IsControl))
            throw new ArgumentException("文件名解析数量/文字超出上限或含控制字符。");
        Regex expression;
        try { expression = new Regex(pattern, RegexOptions.CultureInvariant | RegexOptions.NonBacktracking, TimeSpan.FromMilliseconds(100)); }
        catch (NotSupportedException) { throw new ArgumentException("文件名正则不支持前后查找、反向引用等回溯结构；请使用普通捕获组。"); }
        return names.Select(name =>
        {
            var match = expression.Match(name);
            if (!match.Success) return null;
            var value = match.Result(template);
            return value;
        }).ToArray();
    }
    public static string[] Sequence(string start, long stepSeconds, int count)
    {
        if (count is < 1 or > 3000) throw new ArgumentException("序列数量须为1至3000。");
        var first = Parse(start);
        try { return Enumerable.Range(0, count).Select(index => first.Shift(0, 0, 0, 0, 0, checked(index * stepSeconds)).Text).ToArray(); }
        catch (OverflowException) { throw new ArgumentException("时间序列间隔溢出。"); }
    }
}
