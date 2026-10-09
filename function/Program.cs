using Microsoft.Extensions.Hosting;

// The standard isolated-worker host. Nothing here is specific to Locally: the
// Durable Task Scheduler is selected in host.json and reached through the
// connection string in the app's settings.
var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .Build();

host.Run();
