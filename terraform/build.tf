module "rg" {
  source = "registry.terraform.io/libre-devops/rg/azurerm"

  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-build" // rg-ldo-euw-dev-build
  location = local.location                                            // compares var.loc with the var.regions var to match a long-hand name, in this case, "euw", so "westeurope"
  tags     = local.tags

  #  lock_level = "CanNotDelete" // Do not set this value to skip lock
}

module "plan" {
  source = "registry.terraform.io/libre-devops/service-plan/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  app_service_plan_name          = "asp-${var.short}-${var.loc}-${terraform.workspace}-01"
  add_to_app_service_environment = false

  os_type  = "Windows"
  sku_name = "S1"
}

#checkov:skip=CKV2_AZURE_145:TLS 1.2 is allegedly the latest supported as per hashicorp docs
module "web_app" {
  source = "registry.terraform.io/libre-devops/windows-web-app/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  app_name        = "app-${var.short}-${var.loc}-${terraform.workspace}-01"
  service_plan_id = module.plan.service_plan_id

  storage_uses_managed_identity = "false"

  identity_type = "SystemAssigned"

  settings = {
    site_config = {
      minimum_tls_version = "1.2"
      http2_enabled       = true

      application_stack = {
        python_version = "3.4.0"
      }
    }

    auth_settings = {
      enabled = true
    }
  }
}