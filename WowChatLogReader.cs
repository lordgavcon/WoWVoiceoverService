using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace DACodeTest
{
    public record WowChatMessage(
        string Timestamp,
        string EventType,
        string SenderName,
        string Message,
        string RawLine);

    public static class WowChatLogReader
    {
        // Only channels where the sender is always a real player
        private static readonly HashSet<string> PlayerChatEvents = new(StringComparer.OrdinalIgnoreCase)
        {
            "CHAT_MSG_SAY",
            "CHAT_MSG_YELL",
            "CHAT_MSG_WHISPER",
            "CHAT_MSG_WHISPER_INFORM",
            "CHAT_MSG_PARTY",
            "CHAT_MSG_PARTY_LEADER",
            "CHAT_MSG_RAID",
            "CHAT_MSG_RAID_LEADER",
            "CHAT_MSG_RAID_WARNING",
            "CHAT_MSG_GUILD",
            "CHAT_MSG_OFFICER",
            "CHAT_MSG_CHANNEL",
            "CHAT_MSG_EMOTE",
            "CHAT_MSG_TEXT_EMOTE",
            "CHAT_MSG_BN_WHISPER",
            "CHAT_MSG_BN_WHISPER_INFORM",
            "CHAT_MSG_INSTANCE_CHAT",
            "CHAT_MSG_INSTANCE_CHAT_LEADER",
        };

        private static readonly string[] DefaultLogPaths =
        [
            @"C:\Program Files (x86)\World of Warcraft\_retail_\Logs\WoWChatLog.txt",
            @"C:\Program Files\World of Warcraft\_retail_\Logs\WoWChatLog.txt",
            @"C:\Program Files (x86)\World of Warcraft\_classic_\Logs\WoWChatLog.txt",
            @"C:\Program Files\World of Warcraft\_classic_\Logs\WoWChatLog.txt",
        ];

        public static string? FindDefaultLogPath() => FindLogFile();

        // Reads only lines written after fromPosition, returning the messages and the new file position.
        public static (List<WowChatMessage> Messages, long NextPosition) ReadNewMessages(
            string logPath, long fromPosition)
        {
            var messages = new List<WowChatMessage>();

            using var stream = new FileStream(logPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            if (stream.Length <= fromPosition)
                return (messages, fromPosition);

            stream.Seek(fromPosition, SeekOrigin.Begin);
            using var reader = new StreamReader(stream);

            string? line;
            while ((line = reader.ReadLine()) != null)
            {
                if (!IsPlayerChatLine(line)) continue;
                var msg = ParseLine(line);
                if (msg is not null)
                    messages.Add(msg);
            }

            return (messages, stream.Position);
        }

        public static List<WowChatMessage> ReadLastMessages(int lineCount = 100, string? logPath = null)
        {
            string path = logPath ?? FindLogFile()
                ?? throw new FileNotFoundException("WoW chat log not found. Enable logging in-game with /chatlog.");

            return File.ReadLines(path)
                       .Where(IsPlayerChatLine)
                       .TakeLast(lineCount)
                       .Select(ParseLine)
                       .OfType<WowChatMessage>()
                       .ToList();
        }

        // Log line format: "MM/DD HH:MM:SS.mmm  EVENT_TYPE,GUID,SENDER,LANGUAGE,...,MESSAGE"
        private static WowChatMessage? ParseLine(string line)
        {
            int sep = line.IndexOf("  ", StringComparison.Ordinal);
            if (sep < 0) return null;

            string timestamp = line[..sep];
            var fields = SplitCsv(line[(sep + 2)..]);
            if (fields.Count < 4) return null;

            string eventType = fields[0];
            // Field layout after event type: [0]=GUID, [1]=sender name, [2]=language, ..., [last]=message
            string senderName = fields.Count > 2 ? fields[2].Trim('"') : string.Empty;
            string message    = fields[^1].Trim('"');

            return new WowChatMessage(timestamp, eventType, senderName, message, line);
        }

        private static List<string> SplitCsv(string line)
        {
            var fields = new List<string>();
            var current = new StringBuilder();
            bool inQuotes = false;

            foreach (char c in line)
            {
                if (c == '"')
                {
                    inQuotes = !inQuotes;
                }
                else if (c == ',' && !inQuotes)
                {
                    fields.Add(current.ToString());
                    current.Clear();
                }
                else
                {
                    current.Append(c);
                }
            }

            if (current.Length > 0)
                fields.Add(current.ToString());

            return fields;
        }

        private static bool IsPlayerChatLine(string line)
        {
            int sep = line.IndexOf("  ", StringComparison.Ordinal);
            if (sep < 0) return false;

            int start = sep + 2;
            int end   = line.IndexOfAny([',', ' '], start);
            if (end < 0) end = line.Length;

            return PlayerChatEvents.Contains(line[start..end]);
        }

        private static string? FindLogFile() =>
            DefaultLogPaths.FirstOrDefault(File.Exists);
    }
}
