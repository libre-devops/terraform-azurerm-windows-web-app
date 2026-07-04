# Windows Web App

Terraform module for Azure Windows web apps on App Service plans (dedicated B/S/P, App Service
Environments), in the Libre DevOps style: fast to get going, secure by default, flexible when
it matters.

```hcl
module "windows_web_app" {
  source  = "libre-devops/windows-web-app/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids["rg-ldo-uks-dev-001"]
  location          = "uksouth"
  tags              = module.tags.tags

  web_apps = {
    "app-web-ldo-uks-dev-001" = {
      site_config = { application_stack = { current_stack = "dotnet" } }
    }
  }
}
```

That single entry gets a dedicated B1 plan, a user-assigned identity attached as
"SystemAssigned, UserAssigned", and secure defaults the provider does not give you:
`https_only` on, FTP and WebDeploy basic auth OFF, `ftps_state` defaulted to `Disabled`, and a
`minimum_tls_version` floor of 1.2. Every default has an explicit override.

- **Plans as a map.** Multiple apps share a plan via `service_plan_key`, `service_plan_id`
  brings your own, `app_service_environment_id` places a plan on an ASE, and an app that
  references no plan gets its own B1 automatically.
- **Identity in every shape.** The module-created UAI default (both kinds live), bring your
  own of any type, or none at all; the identity powers App Insights AAD ingestion and
  managed-identity container registry pulls.
- **A deploy story with its eyes open.** Windows web apps always have a Kudu/SCM site, so both
  `az webapp deployment source config-zip` and the Terraform-native `zip_deploy_file` work
  (config-zip verified live here; `zip_deploy_file` verified on the linux sibling, same Kudu
  path). `zip_deploy_file` relies on the basic-auth publishing profile this module disables by
  default, so opting in also needs `webdeploy_publish_basic_authentication_enabled = true` plus
  `WEBSITE_RUN_FROM_PACKAGE` or `SCM_DO_BUILD_DURING_DEPLOYMENT` (a validation enforces the
  pairing). Because that basic-auth surface is a credential you would rather not carry, the
  honest default is the AAD push after apply, which this repo's staged CI does (apply, push the
  static site with a fresh login, confirm the served page carries the example's marker, destroy;
  a plain 200 is not proof, since an undeployed Windows web app already serves the platform's
  default page).
- **Application Insights, AAD-ingestion ready.** Pass the connection string and the AI id and
  the module wires the app setting, the AAD ingestion auth string, and the Monitoring Metrics
  Publisher grant (gated on a plan-known flag).
- **The full provider surface, Windows flavour.** `application_stack` with `current_stack` and
  the Windows runtimes (.NET and .NET Core, Node, PHP, Java with Tomcat/JBoss, Python, and
  Windows containers), the Windows-only `virtual_application` and `handler_mapping` IIS blocks,
  `auth_settings` and `auth_settings_v2` in full, the `logs` block (file system and blob),
  `auto_heal_setting` with all trigger shapes including the Windows `private_memory_kb` ceiling,
  backup, connection strings, sticky settings, storage mounts, IP restrictions with headers, and
  VNet integration.

## Examples

- [`examples/minimal`](./examples/minimal) - the one-entry call above, a static site IIS serves,
  applied and verified in CI.
- [`examples/complete`](./examples/complete) - a shared B1 plan hosting a static .NET-stack site
  (App Insights with AAD ingestion, always_on, a health check, CORS, TLS 1.3) next to a second
  app exercising the Windows-only surface (a virtual application, an IIS handler mapping,
  file-system logs, and an auto-heal rule on a private-memory ceiling).

Slots are a deliberate non-goal for now (`azurerm_windows_web_app_slot` is its own resource and
can compose with this module's outputs).
