using System;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace EQNetwork.Examples
{
    /// <summary>
    /// Automated Video Ingest & Review Pipeline for C# / .NET
    /// Demonstrates chunked video uploading, channel assignment, and status polling.
    /// </summary>
    public class UploadPipeline
    {
        private readonly HttpClient _client = new HttpClient();
        private readonly string _baseUrl;

        public UploadPipeline(string baseUrl = "https://eqnetwork.com/sd")
        {
            _baseUrl = baseUrl.TrimEnd('/');
            if (!_baseUrl.EndsWith("/sd"))
            {
                _baseUrl += "/sd";
            }
        }

        public async Task<string> CreateSessionAsync(string username, string password)
        {
            var content = new FormUrlEncodedContent(new[]
            {
                new System.Collections.Generic.KeyValuePair<string, string>("UserName", username),
                new System.Collections.Generic.KeyValuePair<string, string>("Password", password)
            });

            var response = await _client.PostAsync($"{_baseUrl}/CreateSession.aspx", content);
            response.EnsureSuccessStatusCode();

            var xml = await response.Content.ReadAsStringAsync();
            var doc = XDocument.Parse(xml);
            var sessionGuid = doc.Root?.Element("SessionGuid")?.Value;

            if (string.IsNullOrEmpty(sessionGuid))
            {
                throw new InvalidOperationException($"Authentication failed: {xml}");
            }

            Console.WriteLine($"✓ Authenticated. SessionGuid: {sessionGuid}");
            return sessionGuid;
        }

        public async Task<string> UploadVideoAsync(string sessionGuid, string filePath, string collectionId, string title, string category = "Technology")
        {
            var fileInfo = new FileInfo(filePath);
            if (!fileInfo.Exists) throw new FileNotFoundException("File not found", filePath);

            long chunkSize = 2 * 1024 * 1024; // 2MB
            int totalChunks = (int)Math.Max(1, Math.Ceiling((double)fileInfo.Length / chunkSize));

            // 1. Begin Upload
            var beginContent = new FormUrlEncodedContent(new[]
            {
                new System.Collections.Generic.KeyValuePair<string, string>("SessionGuid", sessionGuid),
                new System.Collections.Generic.KeyValuePair<string, string>("Name", fileInfo.Name),
                new System.Collections.Generic.KeyValuePair<string, string>("OriginalFilepath", fileInfo.Name),
                new System.Collections.Generic.KeyValuePair<string, string>("FileSize", fileInfo.Length.ToString()),
                new System.Collections.Generic.KeyValuePair<string, string>("PreferredChunkSize", chunkSize.ToString()),
                new System.Collections.Generic.KeyValuePair<string, string>("NumberOfChunks", totalChunks.ToString()),
                new System.Collections.Generic.KeyValuePair<string, string>("DeviceIdentifier", Guid.NewGuid().ToString())
            });

            var beginRes = await _client.PostAsync($"{_baseUrl}/Api2.0/Upload2_Begin.aspx", beginContent);
            var beginXml = XDocument.Parse(await beginRes.Content.ReadAsStringAsync());
            var uploadId = beginXml.Root?.Element("Upload")?.Attribute("UploadId")?.Value;

            Console.WriteLine($"✓ Upload session allocated. UploadId: {uploadId}");

            // 2. Upload Chunks
            using (var stream = fileInfo.OpenRead())
            {
                byte[] buffer = new byte[chunkSize];
                for (int i = 0; i < totalChunks; i++)
                {
                    int bytesRead = await stream.ReadAsync(buffer, 0, (int)chunkSize);
                    using (var multipart = new MultipartFormDataContent())
                    {
                        multipart.Add(new StringContent(sessionGuid), "SessionGuid");
                        multipart.Add(new StringContent(uploadId), "UploadId");
                        multipart.Add(new StringContent((i * chunkSize).ToString()), "ChunkOffset");
                        multipart.Add(new StringContent(bytesRead.ToString()), "ChunkSize");

                        var byteContent = new ByteArrayContent(buffer, 0, bytesRead);
                        multipart.Add(byteContent, "Data", "blob");

                        var chunkRes = await _client.PostAsync($"{_baseUrl}/Api2.0/Upload2_UploadChunk.aspx", multipart);
                        chunkRes.EnsureSuccessStatusCode();
                        Console.WriteLine($"  • Uploaded chunk {i + 1}/{totalChunks}");
                    }
                }
            }

            // 3. Complete Upload
            var completeContent = new FormUrlEncodedContent(new[]
            {
                new System.Collections.Generic.KeyValuePair<string, string>("SessionGuid", sessionGuid),
                new System.Collections.Generic.KeyValuePair<string, string>("UploadId", uploadId)
            });
            await _client.PostAsync($"{_baseUrl}/Api2.0/Upload2_Complete.aspx", completeContent);
            Console.WriteLine("✓ Chunks assembled on media server.");

            // 4. Create ContentFile
            var createContent = new FormUrlEncodedContent(new[]
            {
                new System.Collections.Generic.KeyValuePair<string, string>("SessionGuid", sessionGuid),
                new System.Collections.Generic.KeyValuePair<string, string>("UploadId", uploadId),
                new System.Collections.Generic.KeyValuePair<string, string>("CollectionId", collectionId),
                new System.Collections.Generic.KeyValuePair<string, string>("Name", title),
                new System.Collections.Generic.KeyValuePair<string, string>("Description", $"Uploaded automatically via .NET Pipeline at {DateTime.UtcNow}"),
                new System.Collections.Generic.KeyValuePair<string, string>("Categories", category)
            });

            var cfRes = await _client.PostAsync($"{_baseUrl}/Api2.0/Upload2_CreateContentFile.aspx", createContent);
            var cfXml = XDocument.Parse(await cfRes.Content.ReadAsStringAsync());
            var contentFileId = cfXml.Root?.Element("ContentFileId")?.Value;

            Console.WriteLine($"✓ Video registered in channel. ContentFileId: {contentFileId}");
            return contentFileId;
        }

        public static async Task Main(string[] args)
        {
            var pipeline = new UploadPipeline();
            string session = await pipeline.CreateSessionAsync("test222", "fEkcow-majdyh-diggi5");
            Console.WriteLine($"Ready for upload with session {session}");
        }
    }
}
