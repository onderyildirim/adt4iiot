using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using System.Net.Http;
using Azure.Core.Pipeline;
using Microsoft.Azure.WebJobs.Host;
using Microsoft.Azure.EventGrid.Models;
using Microsoft.Azure.WebJobs.Extensions.EventGrid;
using Azure.DigitalTwins.Core;
using Azure.DigitalTwins.Core.Serialization;
using Azure.Identity;
using Newtonsoft.Json.Linq;
using System.Collections.Generic;
using System.Text;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;

namespace ADT4IIOT
{

    class TagId
    {
        private char tagIdSeparator = '.';
        private string _assetId;
        private string _tagName;
        public string assetId
        {
            get { return _assetId; }   // get method
            set { _assetId = value; }  // set method
        }
        public string tagName
        {
            get { return _tagName; }   // get method
            set { _tagName = value; }  // set method
        }
        public TagId(string tagId)
        {
            int i = tagId.LastIndexOf(tagIdSeparator);
            if (i > 0)
            {
                assetId = tagId.Substring(0, i);
                tagName = (i < tagId.Length - 1) ? tagId.Substring(i + 1, tagId.Length - i - 1) : "";
            }
        }

    }

    public static class UpdateTelemetry
    {
        //Your Digital Twins URL is stored in an application setting in Azure Functions.
        private static readonly string adtInstanceUrl;
        private static readonly bool DebugMode;
        private static readonly HttpClient httpClient = new HttpClient();
        private static readonly string mapfileBlobConnectionString;
        private static readonly string mapfileBlobContainer;
        private static readonly string mapfilePath;
        private static readonly char mapfileSeparator;
        private static readonly SortedList<string, string> dtIdMap = new SortedList<string, string>();

        static UpdateTelemetry()
        {
            adtInstanceUrl = Environment.GetEnvironmentVariable("ADT_SERVICE_URL");
            bool.TryParse(Environment.GetEnvironmentVariable("DEBUG_MODE"), out DebugMode);

            //string blobConnectionString = "DefaultEndpointsProtocol=https;AccountName=storage******c9709;AccountKey=v**************************************;EndpointSuffix=core.windows.net";
            //string container = "azure-webjobs-hosts";

            mapfileBlobConnectionString = Environment.GetEnvironmentVariable("MAPFILE_BLOB_CONNECTION_STRING");
            mapfileBlobContainer = Environment.GetEnvironmentVariable("MAPFILE_BLOB_CONTAINERNAME");
            mapfilePath = Environment.GetEnvironmentVariable("MAPFILE_PATH");
            string _mapfileSeparator = Environment.GetEnvironmentVariable("MAPFILE_SEPARATOR") ?? ",";
            mapfileSeparator = _mapfileSeparator.ToCharArray()[0];
            char[] trimChars = { '"', '\'' };

            if (!string.IsNullOrEmpty(mapfileBlobConnectionString) && !string.IsNullOrEmpty(mapfileBlobContainer) && !string.IsNullOrEmpty(mapfilePath))
            {
                BlobContainerClient blobContainerClient = new BlobContainerClient(mapfileBlobConnectionString, mapfileBlobContainer);
                BlobClient blobClient = blobContainerClient.GetBlobClient(mapfilePath);
                var response = blobClient.Download();

                using (var streamReader = new StreamReader(response.Value.Content))
                {
                    //skip first line
                    streamReader.ReadLine();
                    while (!streamReader.EndOfStream)
                    {
                        var lines = streamReader.ReadLine();
                        var linea = lines.Split(mapfileSeparator);
                        if (linea.Length > 1)
                        {
                            var dtId = linea[0].Trim(trimChars);
                            var assetId = linea[1].Trim(trimChars);
                            dtIdMap.Add(assetId, dtId);
                        }
                    }
                }
            }
        }

        [FunctionName("UpdateTelemetry")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req, ExecutionContext ctx, ILogger log)
        {
            if (adtInstanceUrl == null)
            {
                log.LogError("Application setting \"ADT_SERVICE_URL\" not set");
            }
            else
            {
                try
                {
                    string requestBody = await new StreamReader(req.Body).ReadToEndAsync();

                    dynamic dataArray = JsonConvert.DeserializeObject(requestBody);

                    //Authenticate with Digital Twins.
                    ManagedIdentityCredential cred = new ManagedIdentityCredential("https://digitaltwins.azure.net");
                    DigitalTwinsClient client = new DigitalTwinsClient(new Uri(adtInstanceUrl), cred, new DigitalTwinsClientOptions { Transport = new HttpClientTransport(httpClient) });
                    if (DebugMode)
                    {
                        log.LogInformation($"{ctx.InvocationId}: Azure digital twins service client connection created to \"{adtInstanceUrl}\".");
                        log.LogInformation($"{ctx.InvocationId}: Request body size: {requestBody.Length / 1024}kb");
                    }

                    if (requestBody != null)
                    {
                        JArray msgArray = JArray.Parse(requestBody);
                        if (DebugMode)
                        {
                            log.LogInformation($"{ctx.InvocationId}: Request has {msgArray.Count} elements");
                            log.LogInformation($"{ctx.InvocationId}: Request body: \n{requestBody.Replace("},{", "},\n{")}");
                        }

                        foreach (var messageJson in msgArray)
                        {
                            TagId tag = new TagId(messageJson["TagId"].Value<string>());
                            if (DebugMode)
                            {
                                log.LogInformation($"{ctx.InvocationId}: TagId  : {messageJson["TagId"].Value<string>()}");
                                log.LogInformation($"{ctx.InvocationId}: AssetId: {tag.assetId}");
                                log.LogInformation($"{ctx.InvocationId}: TagName: {tag.tagName}");
                                log.LogInformation($"{ctx.InvocationId}: Value  : {messageJson["Value"].Value<Double>()}");
                            }

                            var patch = new Azure.JsonPatchDocument();
                            patch.AppendAdd<double>("/" + tag.tagName, messageJson["Value"].Value<Double>());

                            try
                            {
                                var adtId = assetId2dtId(tag.assetId);
                                if (DebugMode)
                                {
                                    log.LogInformation($"{ctx.InvocationId}: ADT Id : {adtId}");
                                    log.LogInformation($"{ctx.InvocationId}: Patch  : {patch}");
                                    log.LogInformation($"{ctx.InvocationId}: Calling ADT update");
                                }

                                if (!string.IsNullOrWhiteSpace(adtId))
                                {
                                    await client.UpdateDigitalTwinAsync(adtId, patch);
                                }
                            }
                            catch (Exception e)
                            {
                                DumpException(e, ctx.InvocationId.ToString(), log);
                            }
                        }
                    }
                    else
                    {
                        log.LogInformation($"{ctx.InvocationId}: Request body is null");
                    }
                }
                catch (Exception e)
                {

                    DumpException(e, ctx.InvocationId.ToString(), log);
                    return new System.Web.Http.ExceptionResult(e, true);

                }
            }
            return new OkObjectResult("OK");
        }

        private static void DumpException(Exception ex, string Id, ILogger log)
        {
            while (ex != null)
            {
                log.LogError("{0}: {1}: {2} \n{3}\n=======================", Id, ex.GetType().Name, ex.Message, ex.StackTrace);
                ex = ex.InnerException;
            }
        }
        private static string convert2dtId(string assetId)
        {
            char replaceChar = '-';
            HashSet<char> allowedChars = new HashSet<char> {
                    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'V', 'U', 'W', 'X', 'Y', 'Z',
                    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'v', 'u', 'w', 'x', 'y', 'z',
                    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                    '-', '.', '+', '%', '_', '#', '*', '?', '!', '(', ')', ',', '=', '@', '$', '\''
                    };
            var result = new StringBuilder(assetId.Length);
            foreach (char c in assetId)
            {
                if (allowedChars.Contains(c))
                {
                    result.Append(Char.ToLower(c));
                }
                else
                {
                    result.Append(replaceChar);
                }
            }
            return result.ToString();
        }
        private static string assetId2dtId(string assetId)
        {
            string dtId;
            dtIdMap.TryGetValue(assetId, out dtId);
            if (string.IsNullOrEmpty(dtId))
            {
                dtId= convert2dtId(assetId);
            }
            return dtId;
        }

    }
}
