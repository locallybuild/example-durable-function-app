locals {
  # The Function App is deployed from `dotnet publish` output. A hash of that
  # directory names the package, so a rebuild produces a new package name and
  # a redeploy (the provider only redeploys when zip_deploy_file changes).
  publish_dir  = "${path.module}/../../function/publish"
  publish_hash = substr(sha1(join(",", [for f in sort(fileset(local.publish_dir, "**")) : "${f}:${filesha1("${local.publish_dir}/${f}")}"])), 0, 12)

  # The scheduler's endpoint, as the provider reports it; the connection string
  # the Durable extension reads is built from it.
  scheduler_endpoint = azapi_resource.scheduler.output.properties.endpoint
}
