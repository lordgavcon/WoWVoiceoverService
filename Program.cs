using DACodeTest;

static void Log(string msg) =>
    Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] {msg}");

string logPath = WowChatLogReader.FindDefaultLogPath()
    ?? throw new FileNotFoundException(
        "WoW chat log not found. Enable logging in-game with /chatlog first.");

Log($"Monitoring: {logPath}");
Log("Press Ctrl+C to stop.\n");

using var voiceover = WowVoiceoverService.CreateDefault("fbIG6gEosVIM95R5qOna", Log);
using var cts = new CancellationTokenSource();

Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

long filePosition = new FileInfo(logPath).Length;
Log($"Starting at file position {filePosition}");

while (!cts.Token.IsCancellationRequested)
{
    long previousPosition = filePosition;
    var (messages, nextPosition) = WowChatLogReader.ReadNewMessages(logPath, filePosition);
    filePosition = nextPosition;

    if (filePosition != previousPosition)
        Log($"File grew by {filePosition - previousPosition} bytes — {messages.Count} player message(s) found");

    foreach (var msg in messages)
    {
        Log($"Speaking [{msg.EventType}] {msg.SenderName}: {msg.Message}");
        await voiceover.SpeakAsync(msg);
    }

    await Task.Delay(1000, cts.Token).ContinueWith(_ => { });
}

Log("Stopped.");
