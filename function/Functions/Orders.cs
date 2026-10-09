using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.DurableTask;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Logging;

namespace OrderProcessing;

public record OrderItem(string Sku, int Quantity);

public record Order(string CustomerEmail, OrderItem[] Items);

public record Receipt(string OrderId, string Version, string[] Reservations, string Payment, string Notification, DateTime CompletedAt);

// The HTTP side: start an order and read it back. Both go through the durable
// client, which talks to the host's task hub on the Durable Task Scheduler.
public static class OrdersApi
{
    [Function(nameof(StartOrder))]
    public static async Task<HttpResponseData> StartOrder(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "orders")] HttpRequestData req,
        [DurableClient] DurableTaskClient client,
        FunctionContext context)
    {
        var log = context.GetLogger(nameof(StartOrder));
        var order = await JsonSerializer.DeserializeAsync<Order>(req.Body, JsonOptions.Default)
            ?? new Order("nobody@example.com", Array.Empty<OrderItem>());
        if (order.Items.Length == 0)
        {
            var bad = req.CreateResponse(HttpStatusCode.BadRequest);
            await bad.WriteStringAsync("an order needs at least one item: {\"customerEmail\":\"...\",\"items\":[{\"sku\":\"...\",\"quantity\":1}]}");
            return bad;
        }

        var instanceId = await client.ScheduleNewOrchestrationInstanceAsync(nameof(Orchestrations.ProcessOrder), order);
        log.LogInformation("Order {InstanceId} started for {Customer} with {Count} item(s)", instanceId, order.CustomerEmail, order.Items.Length);
        return await client.CreateCheckStatusResponseAsync(req, instanceId);
    }

    [Function(nameof(GetOrder))]
    public static async Task<HttpResponseData> GetOrder(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "orders/{id}")] HttpRequestData req,
        [DurableClient] DurableTaskClient client,
        string id)
    {
        var metadata = await client.GetInstanceAsync(id, getInputsAndOutputs: true);
        if (metadata is null)
        {
            return req.CreateResponse(HttpStatusCode.NotFound);
        }
        var response = req.CreateResponse(HttpStatusCode.OK);
        await response.WriteAsJsonAsync(new
        {
            id = metadata.InstanceId,
            name = metadata.Name,
            status = metadata.RuntimeStatus.ToString(),
            created = metadata.CreatedAt,
            lastUpdated = metadata.LastUpdatedAt,
            input = metadata.SerializedInput,
            output = metadata.SerializedOutput,
        });
        return response;
    }
}

public static class Orchestrations
{
    // ProcessOrder reserves every line in parallel, charges the payment, waits a
    // moment for fulfilment (a durable timer), then tells the customer through a
    // sub-orchestration. It is versioned: orchestrations started before the app
    // declared version 2.0 skip the fraud check, exactly as the orchestration
    // versioning rules intend, so a deploy never breaks an order in flight.
    [Function(nameof(ProcessOrder))]
    public static async Task<Receipt> ProcessOrder(
        [OrchestrationTrigger] TaskOrchestrationContext context)
    {
        var order = context.GetInput<Order>() ?? new Order("nobody@example.com", Array.Empty<OrderItem>());
        var log = context.CreateReplaySafeLogger(nameof(ProcessOrder));

        if (VersionAtLeast(context.Version, 2))
        {
            // Added in version 2.0 of the app.
            await context.CallActivityAsync(nameof(Activities.ScreenForFraud), order);
        }

        var reservations = await Task.WhenAll(order.Items
            .Select(item => context.CallActivityAsync<string>(nameof(Activities.ReserveStock), item)));

        var payment = await context.CallActivityAsync<string>(nameof(Activities.ChargePayment), order);

        // Fulfilment takes a moment. The orchestration is checkpointed on the
        // scheduler while it waits; with extended sessions the worker keeps its
        // state so the resume does not replay from the start.
        await context.CreateTimer(context.CurrentUtcDateTime.AddSeconds(3), CancellationToken.None);

        var notification = await context.CallSubOrchestratorAsync<string>(nameof(NotifyCustomer), order.CustomerEmail);

        log.LogInformation("Order {InstanceId} complete at version {Version}", context.InstanceId, context.Version);
        return new Receipt(context.InstanceId, context.Version, reservations, payment, notification, context.CurrentUtcDateTime);
    }

    [Function(nameof(NotifyCustomer))]
    public static async Task<string> NotifyCustomer(
        [OrchestrationTrigger] TaskOrchestrationContext context)
    {
        var email = context.GetInput<string>() ?? "nobody@example.com";
        return await context.CallActivityAsync<string>(nameof(Activities.SendEmail), email);
    }

    private static bool VersionAtLeast(string version, int major)
    {
        var first = version.Split('.')[0];
        return int.TryParse(first, out var parsed) && parsed >= major;
    }
}

public static class Activities
{
    [Function(nameof(ScreenForFraud))]
    public static string ScreenForFraud([ActivityTrigger] Order order, FunctionContext context)
    {
        context.GetLogger(nameof(ScreenForFraud)).LogInformation("Screened order for {Customer}: clear", order.CustomerEmail);
        return "clear";
    }

    [Function(nameof(ReserveStock))]
    public static string ReserveStock([ActivityTrigger] OrderItem item, FunctionContext context)
    {
        context.GetLogger(nameof(ReserveStock)).LogInformation("Reserved {Quantity} x {Sku}", item.Quantity, item.Sku);
        return $"{item.Quantity} x {item.Sku} reserved";
    }

    [Function(nameof(ChargePayment))]
    public static string ChargePayment([ActivityTrigger] Order order, FunctionContext context)
    {
        var total = order.Items.Sum(i => i.Quantity);
        context.GetLogger(nameof(ChargePayment)).LogInformation("Charged {Customer} for {Total} unit(s)", order.CustomerEmail, total);
        return $"charged {order.CustomerEmail} for {total} unit(s)";
    }

    [Function(nameof(SendEmail))]
    public static string SendEmail([ActivityTrigger] string email, FunctionContext context)
    {
        context.GetLogger(nameof(SendEmail)).LogInformation("Emailed {Email}", email);
        return $"emailed {email}";
    }
}

internal static class JsonOptions
{
    public static readonly JsonSerializerOptions Default = new(JsonSerializerDefaults.Web);
}
