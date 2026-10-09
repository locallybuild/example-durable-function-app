```
ooooo                                      oooo  oooo              
`888'                                      `888  `888              
 888          .ooooo.   .ooooo.   .oooo.    888   888  oooo    ooo 
 888         d88' `88b d88' `\"Y8 `P  )88b   888   888   `88.  .8'
 888         888   888 888        .oP\"888   888   888    `88..8'
 888       o 888   888 888   .o8 d8(  888   888   888     `888'
o888ooooood8 `Y8bod8P' `Y8bod8P' `Y888\"\"8o o888o o888o     .8'
                                                       .o..P'
                                                       `Y8P'
```

# Example: Durable Functions on a Durable Task Scheduler within Locally

This example shows how to deploy a .NET isolated Durable Functions app to [Locally Build](https://locally.build), using a **Durable Task Scheduler** (`Microsoft.DurableTask/schedulers`) as the storage backend. Orchestration state lives in the scheduler's task hub rather than a storage account, and the Function App connects to it with a connection string that authenticates using a **user-assigned managed identity**.

It also turns on orchestration versioning and extended sessions.

```
 Function App (Linux, .NET 8 isolated)                 Durable Task Scheduler
   │                                                      │
   ├─ StartOrder   (HTTP POST /api/orders) ──────────────▶│ task hub "orders"
   │     └─ durable client                                │   ├─ ProcessOrder (orchestration, version 2.0)
   │                                                      │   │    ├─ ScreenForFraud        (activity, v2.0 only)
   ├─ GetOrder     (HTTP GET /api/orders/{id}) ◀──────────│   │    ├─ ReserveStock × items  (activities, fan-out)
   │                                                      │   │    ├─ ChargePayment         (activity)
   ├─ Shop         (HTTP GET /api/shop, demo page)        │   │    ├─ durable timer
   │                                                      │   │    └─ NotifyCustomer        (sub-orchestration)
   └─ orchestrations and activities run here ◀────────────│   └─ dashboard: /_ui/taskhubs/orders
```

The code lives in [`function/`](./function), written in C# with the .NET isolated worker model, alongside the infrastructure that runs it:

* **StartOrder** - `POST /api/orders` with `{"customerEmail": "...", "items": [{"sku": "...", "quantity": 1}]}` starts a `ProcessOrder` orchestration and returns the usual check-status payload.
* **GetOrder** - `GET /api/orders/{id}` returns the orchestration's status, input and (once it's done) the receipt.
* **Shop** - `GET /api/shop` is a small demo page that places orders using the two endpoints above, polls until they finish, and links to the task hub dashboard.
* **ProcessOrder** - reserves each line item in parallel, charges the payment, waits on a durable timer, then calls the `NotifyCustomer` sub-orchestration.

### The scheduler

[`host.json`](./function/host.json) sets the scheduler as the storage provider:

```json
"storageProvider": {
  "type": "azureManaged",
  "connectionStringName": "DURABLE_TASK_SCHEDULER_CONNECTION_STRING"
}
```

Terraform builds the connection string from the scheduler's endpoint, the task hub name and the app's user-assigned identity. That identity has the Durable Task Data Contributor role on the scheduler.

```
Endpoint=https://locally-example-durable-scheduler-<suffix>-berlin.durabletask.locally:5672;TaskHub=orders;Authentication=ManagedIdentity;ClientID=<client id>
```

Schedulers in Locally are reachable at `https://<name>-<suffix>-<region>.durabletask.locally:5672`. The suffix is a short random string generated when the scheduler is created, as it is in Azure, so Terraform reads the endpoint from the scheduler instead of constructing it. You can see yours in the `scheduler_endpoint` output.

The same endpoint also accepts gRPC connections from the portable Durable Task SDKs, so clients outside the Function App can start and query orchestrations too.

### Orchestration versioning

`host.json` sets `"defaultVersion": "2.0"`, so every orchestration this deployment starts is tagged 2.0. `ProcessOrder` checks `context.Version` and only runs the fraud check for 2.0 and above. Instances started by an older deployment (which didn't have that step) replay without it.

`versionMatchStrategy: CurrentOrOlder` allows a 2.0 worker to pick up 1.x instances. `versionFailureStrategy: Reject` means it leaves newer instances for a worker that understands them.

### Extended sessions

With `"extendedSessionsEnabled": true` the worker keeps orchestration state in memory between steps. When an orchestration resumes after a timer or activity, only the new events get sent instead of the full history.

Both features are configured in `host.json`. The only code involved is `ProcessOrder` reading `context.Version`.

## Requirements

* [Locally Build](https://locally.build).
* Either [HashiCorp Terraform](https://terraform.io) or [OpenTofu](https://opentofu.org).
* Either [Docker](https://www.docker.com) or [Podman](https://podman.io) (recommended).
* The [.NET SDK](https://dotnet.microsoft.com/download) 8+, to publish the app. The app targets .NET 8, but newer SDKs build it fine, and `DOTNET_ROLL_FORWARD=LatestMajor` is set so it runs on a newer runtime too.
* The Locally Plugin for `Microsoft.DurableTask` installed (`locally plugin install --name Microsoft.DurableTask`). It isn't in the plugin catalog yet, so for now build it from its repository with `make install`.
* The Locally Plugin for `Microsoft.Storage` installed (`locally plugin install --name Microsoft.Storage`).
* The Locally Plugin for `Microsoft.Web` installed (`locally plugin install --name Microsoft.Web`).

## Running the example

First, make sure your container runtime (Docker or Podman) is running, then start Locally:

```bash
locally build
```

The Function App is deployed from a zip that Terraform builds from the published output in `function/publish`, so publish the app first:

```bash
cd function
dotnet publish -c Release -o publish
cd ..
```

With Locally running, open another terminal and initialise Terraform. This downloads the providers and sets up the module:

```bash
cd environments/locally
terraform init
```

> [!NOTE]
> You can use OpenTofu instead by running `tofu` wherever this says `terraform`.

Once Terraform is initialised, provision the example:

```bash
locally run terraform apply
```

One apply creates the scheduler and task hub, a Storage Account for the Functions host's own state, the managed identity and its role assignments, and the Function App, then pushes the code into the app. When it finishes, the URLs are in the outputs:

```
orders_url             = "https://locally-example-durable-func.furnace.locally:5663/api/orders"
shop_url               = "https://locally-example-durable-func.furnace.locally:5663/api/shop"
scheduler_endpoint     = "https://locally-example-durable-scheduler-<suffix>-berlin.durabletask.locally:5672"
task_hub_dashboard_url = "https://locally-example-durable-scheduler-<suffix>-berlin.durabletask.locally:5672/_ui/taskhubs/orders"
```

[Open the shop page](https://locally-example-durable-func.furnace.locally:5663/api/shop) in a browser. Place an order, wait for it to go from `Running` to `Completed`, then click through to the dashboard to see the orchestration history.

---

You can do the same from the command line. To start an order:

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"customerEmail": "sam@example.com", "items": [{"sku": "WIDGET", "quantity": 2}, {"sku": "GADGET", "quantity": 1}]}' \
  "$(locally run terraform output -raw orders_url)"
```

The response includes the instance ID (`Id`) and a `StatusQueryGetUri`. The timer waits three seconds, so give it a moment before checking on the order:

```bash
curl -s "$(locally run terraform output -raw orders_url)/<instance id>"
```

The receipt lists the orchestration version, each reservation, the payment and the notification. The task hub dashboard (`task_hub_dashboard_url`) shows the orchestration, its sub-orchestration and their histories.

## Notes

The activities are placeholders. `ScreenForFraud`, `ReserveStock`, `ChargePayment` and `SendEmail` each log a line and return a string saying what they would have done. Nothing is charged and no email goes out; `emailed sam@example.com` on the receipt is just `SendEmail`'s return value. You could swap in real calls (a payment API, SMTP) without touching the orchestrations.

The HTTP functions use `AuthorizationLevel.Anonymous` to keep the example focused on the scheduler. In a real app you'd want a function key or proper authentication.

In Locally, the Function App and the scheduler run in the same process, so the app works on the task hub directly instead of streaming work items from it. This isn't visible from the outside: an orchestration started via the app, its durable client or a Durable Task SDK client ends up in the same hub and runs on the same functions.

You can also connect a portable Durable Task SDK worker to the scheduler, either instead of the Function App or alongside it. Point `Microsoft.DurableTask.Worker.AzureManaged`, `durabletask-go`, or the Python, Java or JavaScript SDK at the scheduler's endpoint and task hub (using the same connection string format as the app) and it'll receive work items. As in Azure, a Function App and a worker without work-item filters will compete for orchestrations on a shared hub, so either give each one its own task hub or use filters.

Terraform writes the package to `.build/function-<hash>.zip`, where the hash is computed over `function/publish`. The provider only redeploys when `zip_deploy_file` changes, so re-run `dotnet publish` after editing the code or your changes won't be picked up on the next apply.

## Tearing it down

```bash
cd environments/locally
locally run terraform destroy
```
