# The module's full infrastructure surface on one shared plan: a static .NET-stack site with
# Application Insights AAD ingestion, always_on, a health check, CORS and a TLS 1.3 floor, next
# to a second app exercising the Windows-only surface (a virtual application, an IIS handler
# mapping, file-system logs, and an auto-heal rule that recycles on a private-memory ceiling or a
# burst of server errors). Backup, blob-shipped logs, and storage mounts are exposed by the
# module but not exercised here (all need caller-owned secrets). The site is pushed by the CI
# deploy stage. Applied then destroyed in one CI run.
locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-004"
  law_name  = "log-${var.short}-${var.loc}-${terraform.workspace}-004"
  appi_name = "appi-${var.short}-${var.loc}-${terraform.workspace}-004"
  api_name  = "app-wapi-${var.short}-${var.loc}-${terraform.workspace}-004"
  feat_name = "app-wfeat-${var.short}-${var.loc}-${terraform.workspace}-004"
  plan_name = "asp-shared-${var.short}-${var.loc}-${terraform.workspace}-004"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "terraform-azurerm-windows-web-app" }
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

module "log_analytics" {
  source  = "libre-devops/log-analytics-workspace/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  log_analytics_workspaces = { (local.law_name) = {} }
}

module "application_insights" {
  source  = "libre-devops/application-insights/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  application_insights = {
    (local.appi_name) = {
      workspace_id = module.log_analytics.workspace_ids[local.law_name]
    }
  }
}

module "windows_web_app" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  service_plans = {
    (local.plan_name) = {
      sku_name = "B1"
    }
  }

  web_apps = {
    # The API: a static site IIS serves, App Insights with AAD ingestion, and the site_config
    # surface exercised. Deployed and verified by CI.
    (local.api_name) = {
      service_plan_key = local.plan_name

      app_insights_connection_string       = module.application_insights.connection_strings[local.appi_name]
      app_insights_id                      = module.application_insights.ids[local.appi_name]
      grant_app_insights_metrics_publisher = true

      site_config = {
        always_on                         = true
        health_check_path                 = "/"
        health_check_eviction_time_in_min = 5
        http2_enabled                     = true
        minimum_tls_version               = "1.3"

        application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" }

        cors = {
          allowed_origins = ["https://portal.azure.com"]
        }
      }

      tags = { Component = "api" }
    }

    # The features app: the Windows-only surface (virtual application, IIS handler mapping,
    # file-system logs, auto-heal on a private-memory ceiling or a burst of server errors) plus
    # the keys-on opt-out with a system-assigned identity. Provisioned, not code-deployed.
    (local.feat_name) = {
      service_plan_key = local.plan_name

      create_user_assigned_identity = false
      identity                      = { type = "SystemAssigned" }

      logs = {
        detailed_error_messages = true
        failed_request_tracing  = true
        application_logs        = { file_system_level = "Information" }
        http_logs = {
          file_system = {
            retention_in_days = 3
            retention_in_mb   = 35
          }
        }
      }

      site_config = {
        always_on = true

        application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" }

        virtual_applications = [{
          physical_path = "site\\wwwroot"
          preload       = true
          virtual_path  = "/"
        }]

        handler_mappings = [{
          extension             = ".cgi"
          script_processor_path = "C:\\Windows\\System32\\cmd.exe"
        }]

        auto_heal_setting = {
          action = { action_type = "Recycle" }
          trigger = {
            private_memory_kb = 1048576
            status_code = [{
              count             = 10
              interval          = "00:05:00"
              status_code_range = "500-599"
            }]
          }
        }
      }

      tags = { Component = "features" }
    }
  }
}

output "api_default_hostname" {
  value = module.windows_web_app.default_hostnames[local.api_name]
}

output "api_web_app_name" {
  value = local.api_name
}

output "resource_group_name" {
  value = local.rg_name
}
