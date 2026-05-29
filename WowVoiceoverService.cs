using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Json;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace DACodeTest
{
    public class WowVoiceoverService : IDisposable
    {
        private readonly HttpClient _http;
        private readonly string _defaultVoiceName;
        private readonly Action<string> _log;
        private string? _cachedVoiceId;

        // Reads the key from the ELEVENLABS_API_KEY env var; voice names follow
        // the wow-voiceover convention: "{race}-{gender}" e.g. "human-male", "orc-female"
        public static WowVoiceoverService CreateDefault(
            string defaultVoiceName = "fbIG6gEosVIM95R5qOna",
            Action<string>? logger = null)
        {
            string key = Environment.GetEnvironmentVariable("ELEVENLABS_API_KEY")
                ?? throw new InvalidOperationException(
                    "Set the ELEVENLABS_API_KEY environment variable before calling CreateDefault().");
            return new WowVoiceoverService(key, defaultVoiceName, logger);
        }

        public WowVoiceoverService(
            string elevenLabsApiKey,
            string defaultVoiceName = "fbIG6gEosVIM95R5qOna",
            Action<string>? logger = null)
        {
            _defaultVoiceName = defaultVoiceName;
            _log = logger ?? (_ => { });
            _http = new HttpClient();
            _http.DefaultRequestHeaders.Add("xi-api-key", elevenLabsApiKey);
        }

        public async Task SpeakAsync(WowChatMessage message)
        {
            if (string.IsNullOrWhiteSpace(message.Message))
                return;

            if (_cachedVoiceId is null)
            {
                _log($"Fetching voice by name or ID \"{_defaultVoiceName}\"...");
                _cachedVoiceId = await FetchVoiceIdAsync(_defaultVoiceName);
                _log(_cachedVoiceId is not null
                    ? $"Using voice ID: {_cachedVoiceId}"
                    : "No matching voice found — skipping");
            }

            if (_cachedVoiceId is null)
                return;

            _log($"Requesting TTS for: \"{message.Message}\"");
            byte[] audio = await GenerateAudioAsync(message.Message, _cachedVoiceId);
            _log($"Received {audio.Length} bytes — playing...");

            string tempFile = Path.Combine(Path.GetTempPath(), $"wow_voice_{Guid.NewGuid():N}.mp3");
            try
            {
                await File.WriteAllBytesAsync(tempFile, audio);
                PlayMp3Sync(tempFile);
                _log("Playback complete");
            }
            finally
            {
                if (File.Exists(tempFile))
                    File.Delete(tempFile);
            }
        }

        private async Task<string?> FetchVoiceIdAsync(string nameOrId)
        {
            var response = await _http.GetFromJsonAsync<VoicesResponse>(
                "https://api.elevenlabs.io/v1/voices");

            if (response is null) return null;

            // Accept either a voice name ("human-male") or a raw voice ID
            return response.Voices
                .FirstOrDefault(v =>
                    v.Name.Equals(nameOrId, StringComparison.OrdinalIgnoreCase) ||
                    v.VoiceId.Equals(nameOrId, StringComparison.OrdinalIgnoreCase))
                ?.VoiceId;
        }

        private async Task<byte[]> GenerateAudioAsync(string text, string voiceId)
        {
            // Settings mirror the wow-voiceover project defaults
            var payload = new
            {
                text,
                voice_settings = new { stability = 0.28, similarity_boost = 0.992 }
            };

            var content = new StringContent(
                JsonSerializer.Serialize(payload),
                Encoding.UTF8,
                "application/json");

            var response = await _http.PostAsync(
                $"https://api.elevenlabs.io/v1/text-to-speech/{voiceId}",
                content);

            response.EnsureSuccessStatusCode();
            return await response.Content.ReadAsByteArrayAsync();
        }

        // Windows MCI — plays MP3 without opening a media player window
        [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
        private static extern int mciSendString(
            string command, StringBuilder? buffer, int bufferSize, IntPtr hwnd);

        private static void PlayMp3Sync(string path)
        {
            string alias = $"track_{Path.GetFileNameWithoutExtension(path)}";
            mciSendString($"open \"{path}\" type mpegvideo alias {alias}", null, 0, IntPtr.Zero);
            mciSendString($"play {alias} wait", null, 0, IntPtr.Zero);
            mciSendString($"close {alias}", null, 0, IntPtr.Zero);
        }

        public void Dispose() => _http.Dispose();

        private record VoicesResponse(
            [property: JsonPropertyName("voices")] List<ElevenLabsVoice> Voices);

        private record ElevenLabsVoice(
            [property: JsonPropertyName("voice_id")] string VoiceId,
            [property: JsonPropertyName("name")] string Name);
    }
}
