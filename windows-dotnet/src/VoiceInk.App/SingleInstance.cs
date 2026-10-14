using System.IO.Pipes;

namespace VoiceInk.App;

/// <summary>
/// Keeps one VoiceInk per user session. A second launch hands its command (<c>dashboard</c>, <c>settings</c>) to the
/// running instance over a named pipe and exits.
/// </summary>
internal sealed class SingleInstance : IDisposable
{
    private static readonly string Name = $"VoiceInk.{Environment.UserName}";
    private readonly Mutex _mutex;
    private readonly CancellationTokenSource _stop = new();

    private SingleInstance(Mutex mutex) => _mutex = mutex;

    /// <summary>Returns the instance guard, or null when another instance already owns the session.</summary>
    public static SingleInstance? TryAcquire()
    {
        var mutex = new Mutex(initiallyOwned: true, Name, out var created);
        if (created) return new SingleInstance(mutex);
        mutex.Dispose();
        return null;
    }

    /// <summary>Tells the running instance what to show.</summary>
    public static void Forward(string command)
    {
        try
        {
            using var client = new NamedPipeClientStream(".", Name, PipeDirection.Out);
            client.Connect(2000);
            using var writer = new StreamWriter(client) { AutoFlush = true };
            writer.WriteLine(command);
        }
        catch (Exception e) when (e is TimeoutException or IOException)
        {
            // The other instance is shutting down; nothing to forward to.
        }
    }

    /// <summary>Listens for commands from later launches.</summary>
    public void Listen(Action<string> onCommand)
    {
        _ = Task.Run(async () =>
        {
            while (!_stop.IsCancellationRequested)
            {
                try
                {
                    await using var server = new NamedPipeServerStream(Name, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                    await server.WaitForConnectionAsync(_stop.Token);
                    using var reader = new StreamReader(server);
                    if (await reader.ReadLineAsync(_stop.Token) is { Length: > 0 } line) onCommand(line);
                }
                catch (OperationCanceledException)
                {
                    return;
                }
                catch (IOException)
                {
                    // Client vanished mid-message; keep listening.
                }
            }
        });
    }

    public void Dispose()
    {
        _stop.Cancel();
        _mutex.ReleaseMutex();
        _mutex.Dispose();
    }
}
