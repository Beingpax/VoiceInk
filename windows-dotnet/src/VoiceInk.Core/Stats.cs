using VoiceInk.Core.Text;

namespace VoiceInk.Core;

public sealed class DashboardStats
{
    public int Sessions { get; set; }
    public int Words { get; set; }

    /// <summary>Total recorded audio, seconds.</summary>
    public double DurationSecs { get; set; }

    /// <summary>Estimated typing time minus speaking time, seconds (never negative).</summary>
    public double TimeSavedSecs { get; set; }

    /// <summary>Speaking speed in words per minute.</summary>
    public double Wpm { get; set; }

    public int EnhancedSessions { get; set; }

    /// <summary>Consecutive days with at least one dictation, ending today or yesterday.</summary>
    public int StreakDays { get; set; }

    /// <summary>Words per day, oldest first, for the activity chart.</summary>
    public List<(DateOnly Date, int Words)> DailyWords { get; set; } = [];

    /// <summary>Sessions per hour of day (0..23).</summary>
    public int[] HourlySessions { get; } = new int[24];

    /// <summary>Most used applications: (process name, sessions).</summary>
    public List<(string App, int Sessions)> TopApps { get; set; } = [];
}

public static class Stats
{
    /// <summary>Same assumption as <c>DashboardTimeSaving.averageTypingSpeedWordsPerMinute</c>.</summary>
    public const double TypingWpm = 40.0;

    public static double TimeSaved(int words, double durationSecs) =>
        Math.Max(0, (words / TypingWpm * 60.0) - durationSecs);

    /// <summary>Aggregates completed entries; <paramref name="days"/> controls the length of the daily chart.</summary>
    public static DashboardStats Compute(IEnumerable<HistoryEntry> entries, int days, DateOnly today)
    {
        var s = new DashboardStats();
        var start = today.AddDays(-Math.Max(0, days - 1));
        var daily = new int[days];
        var activeDays = new HashSet<DateOnly>();
        var apps = new Dictionary<string, int>();

        foreach (var e in entries.Where(e => e.Status == EntryStatus.Completed))
        {
            var words = Words.Count(e.FinalText);
            s.Sessions++;
            s.Words += words;
            s.DurationSecs += e.Duration;
            if (!string.IsNullOrEmpty(e.EnhancedText)) s.EnhancedSessions++;
            var date = DateOnly.FromDateTime(e.Timestamp.LocalDateTime);
            activeDays.Add(date);
            if (date >= start && date <= today) daily[date.DayNumber - start.DayNumber] += words;
            s.HourlySessions[e.Timestamp.LocalDateTime.Hour]++;
            if (!string.IsNullOrEmpty(e.App))
            {
                apps[e.App] = apps.GetValueOrDefault(e.App) + 1;
            }
        }

        s.TimeSavedSecs = TimeSaved(s.Words, s.DurationSecs);
        s.Wpm = s.DurationSecs > 0 ? s.Words / (s.DurationSecs / 60.0) : 0;
        s.DailyWords = daily.Select((w, i) => (start.AddDays(i), w)).ToList();

        // Streak counts back from today (or yesterday, so it survives until you dictate today).
        var day = activeDays.Contains(today) ? today : today.AddDays(-1);
        while (activeDays.Contains(day))
        {
            s.StreakDays++;
            day = day.AddDays(-1);
        }

        s.TopApps = apps
            .OrderByDescending(kv => kv.Value).ThenBy(kv => kv.Key, StringComparer.Ordinal)
            .Take(5).Select(kv => (kv.Key, kv.Value)).ToList();
        return s;
    }

    public static DashboardStats ComputeNow(IEnumerable<HistoryEntry> entries, int days) =>
        Compute(entries, days, DateOnly.FromDateTime(DateTime.Now));

    /// <summary>"1 h 05 min", "12 min", "45 s".</summary>
    public static string FormatDuration(double secs)
    {
        var total = (long)Math.Round(Math.Max(0, secs), MidpointRounding.AwayFromZero);
        return total switch
        {
            >= 3600 => $"{total / 3600} h {(total % 3600) / 60:00} min",
            >= 60 => $"{total / 60} min",
            _ => $"{total} s",
        };
    }

    /// <summary>"12,345".</summary>
    public static string FormatCount(long n) => n.ToString("N0", System.Globalization.CultureInfo.InvariantCulture);
}
