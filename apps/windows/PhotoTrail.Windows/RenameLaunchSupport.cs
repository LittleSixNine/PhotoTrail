using System.Text.RegularExpressions;

namespace PhotoTrail.Windows;

// Structural decoding remains available for old libraries and recovery records.
// Availability is checked for the whole scheme, including disabled rules.
internal static class RenameLaunchSupport
{
    internal const string DeferredMessage = "音乐相关功能本次Windows首发暂缓；整份方案保留但不可用，包括已禁用的音乐规则。";
    internal static bool DeferredAction(int action) => action is >= 72 and <= 77;
    static bool MusicToken(string token)
    {
        if (token.Contains(':')) return false; // Exact photo metadata fields retain their ordinary meaning.
        if (token.StartsWith('0')) token = token[1..];
        if (token is "ARTIST" or "artist" or "Song" or "Album" or "AlbumArtist" or "Track" or "TrackNum" or "NumTracks" or "CDNum" or "numCds" or "AudioSampleRate" or "DurationInSeconds" or "Duration_MM_SS" or "Duration_HH_MM_SS" or "Album_Artist_sentence_case") return true;
        return new[] { "Artist", "Album", "Song", "AlbumArtist" }.Any(basis =>
            new[] { "Upper", "Lower", "Capitalized", "sentence_case" }.Any(style => token == basis + "_" + style));
    }
    internal static bool Deferred(RenameRule rule) => rule.Kind == "action" &&
        RenameTransform.Actions.TryGetValue(rule.Action, out var action) &&
        (DeferredAction(action) || action is >= 66 and <= 71 &&
            Regex.Matches(rule.Text, "<([^<>]+)>").Any(match => MusicToken(match.Groups[1].Value)));
    internal static void RequireAvailable(IEnumerable<RenameRule> rules)
    {
        if (rules.Any(Deferred)) throw new InvalidOperationException(DeferredMessage);
    }
}
