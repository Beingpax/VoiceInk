using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;

namespace VoiceInk.Core.Transcription.Local;

public enum DownloadPhase { Downloading, Unpacking }

/// <param name="Fraction">0..1; meaningless while <see cref="DownloadPhase.Unpacking"/>.</param>
/// <param name="BytesPerSecond">Smoothed transfer rate.</param>
public readonly record struct DownloadProgress(DownloadPhase Phase, double Fraction, double BytesPerSecond);

/// <summary>
/// Fast file download. A single TCP stream rarely fills a fast line (CDNs throttle per connection), so the file is
/// fetched as 8 MB ranges over several connections at once and written in place. Servers without range support fall
/// back to one stream. Progress is reported a few times per second, never per chunk.
/// </summary>
public static class FileDownloader
{
    public const int Connections = 8;
    private const long ChunkSize = 8 * 1024 * 1024;
    private const long MinParallelSize = 16 * 1024 * 1024;
    private const int CopyBuffer = 256 * 1024;
    private const int MaxAttempts = 4;
    private static readonly TimeSpan StallTimeout = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan ReportInterval = TimeSpan.FromMilliseconds(150);

    // No automatic decompression: byte ranges must address the file as stored.
    private static readonly HttpClient Client = new(new SocketsHttpHandler
    {
        ConnectTimeout = TimeSpan.FromSeconds(15),
        MaxConnectionsPerServer = 16,
        EnableMultipleHttp2Connections = true,
        AutomaticDecompression = DecompressionMethods.None,
    })
    {
        Timeout = Timeout.InfiniteTimeSpan,
    };

    public static async Task DownloadAsync(
        string url, string destination, IProgress<DownloadProgress>? progress, CancellationToken ct, long knownSize = 0)
    {
        var (total, ranges) = await ProbeAsync(url, ct).ConfigureAwait(false);
        if (total <= 0) total = knownSize;

        var counter = new ByteCounter();
        using var reporting = CancellationTokenSource.CreateLinkedTokenSource(ct);
        var reporter = Report(counter, total, progress, reporting.Token);
        try
        {
            if (ranges && total >= MinParallelSize)
            {
                await ParallelAsync(url, destination, total, counter, ct).ConfigureAwait(false);
            }
            else
            {
                await SingleAsync(url, destination, counter, ct).ConfigureAwait(false);
            }
        }
        finally
        {
            await reporting.CancelAsync().ConfigureAwait(false);
            await reporter.ConfigureAwait(false);
        }

        progress?.Report(new DownloadProgress(DownloadPhase.Downloading, 1, 0));
    }

    private sealed class ByteCounter
    {
        private long _bytes;
        public long Bytes => Interlocked.Read(ref _bytes);
        public void Add(long n) => Interlocked.Add(ref _bytes, n);
    }

    /// <summary>Asks for the first byte: a 206 answer reveals the total size and proves range support.</summary>
    private static async Task<(long Total, bool Ranges)> ProbeAsync(string url, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url) { Headers = { Range = new RangeHeaderValue(0, 0) } };
        using var response = await Client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        if (response.StatusCode == HttpStatusCode.PartialContent && response.Content.Headers.ContentRange?.Length is { } length)
        {
            return (length, true);
        }

        return (response.Content.Headers.ContentLength ?? 0, false);
    }

    private static async Task ParallelAsync(string url, string destination, long total, ByteCounter counter, CancellationToken ct)
    {
        using var handle = File.OpenHandle(
            destination, FileMode.Create, FileAccess.Write, FileShare.None, FileOptions.Asynchronous, preallocationSize: total);
        var chunks = (int)((total + ChunkSize - 1) / ChunkSize);
        var next = -1;
        var workers = Enumerable.Range(0, Math.Min(Connections, chunks)).Select(_ => Task.Run(async () =>
        {
            int chunk;
            while ((chunk = Interlocked.Increment(ref next)) < chunks)
            {
                var from = chunk * ChunkSize;
                var to = Math.Min(from + ChunkSize, total) - 1;
                await FetchChunkAsync(url, handle, from, to, counter, ct).ConfigureAwait(false);
            }
        }, ct)).ToArray();
        await Task.WhenAll(workers).ConfigureAwait(false);
    }

    /// <summary>Downloads bytes [from, to] to the same offsets, retrying the whole chunk on failure or stall.</summary>
    private static async Task FetchChunkAsync(
        string url, Microsoft.Win32.SafeHandles.SafeFileHandle handle, long from, long to, ByteCounter counter, CancellationToken ct)
    {
        for (var attempt = 1; ; attempt++)
        {
            long received = 0;
            using var stall = CancellationTokenSource.CreateLinkedTokenSource(ct);
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, url) { Headers = { Range = new RangeHeaderValue(from, to) } };
                stall.CancelAfter(StallTimeout);
                using var response = await Client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, stall.Token).ConfigureAwait(false);
                if (response.StatusCode != HttpStatusCode.PartialContent)
                {
                    throw new HttpRequestException($"server ignored the range request ({(int)response.StatusCode})");
                }

                await using var body = await response.Content.ReadAsStreamAsync(stall.Token).ConfigureAwait(false);
                var buffer = new byte[CopyBuffer];
                int read;
                while ((read = await ReadWithStallGuard(body, buffer, stall)) > 0)
                {
                    await RandomAccess.WriteAsync(handle, buffer.AsMemory(0, read), from + received, ct).ConfigureAwait(false);
                    received += read;
                    counter.Add(read);
                }

                if (received != to - from + 1) throw new IOException("the connection closed early");
                return;
            }
            catch (Exception e) when (attempt < MaxAttempts && !ct.IsCancellationRequested
                                      && e is HttpRequestException or IOException or OperationCanceledException)
            {
                counter.Add(-received); // this chunk starts over
                await Task.Delay(TimeSpan.FromMilliseconds(300 * attempt), ct).ConfigureAwait(false);
            }
        }
    }

    private static async ValueTask<int> ReadWithStallGuard(Stream body, byte[] buffer, CancellationTokenSource stall)
    {
        stall.CancelAfter(StallTimeout); // resets the timer: only a silent connection counts as stalled
        return await body.ReadAsync(buffer, stall.Token).ConfigureAwait(false);
    }

    private static async Task SingleAsync(string url, string destination, ByteCounter counter, CancellationToken ct)
    {
        using var response = await Client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        await using var body = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        await using var file = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20, useAsync: true);
        var buffer = new byte[1 << 20];
        int read;
        while ((read = await body.ReadAsync(buffer, ct).ConfigureAwait(false)) > 0)
        {
            await file.WriteAsync(buffer.AsMemory(0, read), ct).ConfigureAwait(false);
            counter.Add(read);
        }
    }

    private static async Task Report(ByteCounter counter, long total, IProgress<DownloadProgress>? progress, CancellationToken stop)
    {
        if (progress is null) return;
        using var timer = new PeriodicTimer(ReportInterval);
        var clock = Stopwatch.StartNew();
        long lastBytes = 0;
        var lastTime = TimeSpan.Zero;
        double rate = 0;
        try
        {
            while (await timer.WaitForNextTickAsync(stop).ConfigureAwait(false))
            {
                var bytes = counter.Bytes;
                var now = clock.Elapsed;
                var instant = (bytes - lastBytes) / Math.Max(0.001, (now - lastTime).TotalSeconds);
                rate = rate == 0 ? instant : (rate * 0.7) + (instant * 0.3);
                (lastBytes, lastTime) = (bytes, now);
                progress.Report(new DownloadProgress(DownloadPhase.Downloading, total > 0 ? Math.Min(1.0, (double)bytes / total) : 0, rate));
            }
        }
        catch (OperationCanceledException)
        {
            // Download finished or was canceled.
        }
    }
}
