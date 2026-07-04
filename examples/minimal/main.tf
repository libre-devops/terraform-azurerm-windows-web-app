# Minimal call, and the module's whole point: one entry with nothing but a runtime gets a
# dedicated B1 plan, a user-assigned identity, and secure defaults (https_only on, FTP and
# WebDeploy basic auth off, ftps_state Disabled, TLS 1.2 floor). The app/ folder is a static
# site IIS serves out of the box; the CI deploy stage pushes it with the AAD config-zip path.
# Applied then destroyed in one CI run.
locals {
  location = lookup(var.regions, var.loc, "uksouth")
  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-003"
  app_name = "app-wweb-${var.short}-${var.loc}-${terraform.workspace}-003"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

module "windows_web_app" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  web_apps = {
    (local.app_name) = {
      site_config = { application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" } }
    }
  }
}

output "default_hostname" {
  value = module.windows_web_app.default_hostnames[local.app_name]
}

output "resource_group_name" {
  value = local.rg_name
}

output "web_app_name" {
  value = local.app_name
}
