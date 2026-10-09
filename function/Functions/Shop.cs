using System.Net;
using System.Reflection;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace OrderProcessing;

// A small page for demonstrating the app: place an order, watch its
// orchestration run and read the receipt. It is served by the app itself so it
// calls /api/orders on the same origin, with no CORS to configure.
public static class ShopPage
{
    private static readonly Lazy<string> Template = new(() =>
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("OrderProcessing.Shop.shop.html")
            ?? throw new InvalidOperationException("the shop page is not embedded in the assembly");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    });

    [Function(nameof(Shop))]
    public static async Task<HttpResponseData> Shop(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "shop")] HttpRequestData req)
    {
        // Terraform sets the dashboard's URL; without it the page hides the link.
        var dashboard = Environment.GetEnvironmentVariable("TASK_HUB_DASHBOARD_URL") ?? "";
        var response = req.CreateResponse(HttpStatusCode.OK);
        response.Headers.Add("Content-Type", "text/html; charset=utf-8");
        await response.WriteStringAsync(Template.Value.Replace("{{DASHBOARD_URL}}", WebUtility.HtmlEncode(dashboard)));
        return response;
    }
}
