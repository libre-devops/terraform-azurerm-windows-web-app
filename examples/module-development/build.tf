module "rg" {
  source = "libre-devops/rg/azurerm"

  rg_name  = "rg-${var.short}-${var.loc}-${var.env}-01"
  location = local.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "uid" {
  name                = "uid-${var.short}-${var.loc}-${var.env}-01"
  resource_group_name = module.rg.rg_name
  location            = module.rg.rg_location
  tags                = module.rg.rg_tags
}

module "shared_vars" {
  source = "libre-devops/shared-vars/azurerm"
}

locals {
  lookup_cidr = {
    for landing_zone, envs in module.shared_vars.cidrs : landing_zone => {
      for env, cidr in envs : env => cidr
    }
  }
}

module "subnet_calculator" {
  source = "libre-devops/subnet-calculator/null"

  base_cidr    = local.lookup_cidr[var.short][var.env][0]
  subnet_sizes = [26, 26, 26]
}

module "network" {
  source = "libre-devops/network/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vnet_name          = "vnet-${var.short}-${var.loc}-${var.env}-01"
  vnet_location      = module.rg.rg_location
  vnet_address_space = [module.subnet_calculator.base_cidr]

  subnets = {
    for i, name in module.subnet_calculator.subnet_names :
    name => {
      address_prefixes  = toset([module.subnet_calculator.subnet_ranges[i]])
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]

      # Only assign delegation to subnet3
      delegation = name == "subnet3" ? [
        {
          type = "Microsoft.Web/serverFarms" # Delegation type for subnet3
        },
      ] : []
    }
  }
}


data "http" "user_ip" {
  url = "https://checkip.amazonaws.com"
}

module "role_assignments" {
  source = "github.com/libre-devops/terraform-azurerm-role-assignment"

  role_assignments = [
    {
      principal_ids = [azurerm_user_assigned_identity.uid.principal_id]
      role_names    = ["Key Vault Administrator", "Storage Blob Data Owner", "Storage Blob Data Reader"]
      scope         = module.rg.rg_id
    },
    {
      principal_ids = [module.windows_web_app.web_app_identities["app-${var.short}-${var.loc}-${var.env}-01"].principal_id]
      role_names    = ["Key Vault Administrator", "Storage Blob Data Owner", "Storage Blob Data Reader", "Key Vault Secrets Officer", "Storage Account Contributor"]
      scope         = module.rg.rg_id
    },
  ]
}
module "law" {
  source = "libre-devops/log-analytics-workspace/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  law_name                   = "law-${var.short}-${var.loc}-${var.env}-01"
  law_sku                    = "PerGB2018"
  retention_in_days          = "30"
  daily_quota_gb             = "0.5"
  internet_ingestion_enabled = false
  internet_query_enabled     = false
}


module "windows_web_app" {
  source = "../../"

  depends_on = [module.law]

  # Application Insights Configuration
  windows_web_apps = [
    {
      name     = "app-${var.short}-${var.loc}-${var.env}-01"
      rg_name  = module.rg.rg_name
      location = module.rg.rg_location
      tags     = module.rg.rg_tags

      os_type  = "Windows"
      sku_name = "S1"
      app_settings = {
        "DOTNET_ENVIRONMENT"                     = "Production"
        "WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED" = "1"
        "AzureSubscriptionId"                    = data.azurerm_client_config.current_creds.subscription_id # Replace with actual value
        "StorageAccountResourceGroup"            = module.rg.rg_name                                        # Replace with actual value         # Replace with actual value
      }
      builtin_logging_enabled       = true
      public_network_access_enabled = true
      virtual_network_subnet_id     = module.network.subnets_ids["subnet3"]
      identity_type                 = "SystemAssigned"


      create_new_app_insights                            = true
      workspace_id                                       = module.law.law_id
      app_insights_name                                  = "appi-fnc-${var.short}-${var.loc}-${var.env}-01"
      app_insights_type                                  = "web"
      app_insights_daily_cap_in_gb                       = 0.5
      app_insights_daily_data_cap_notifications_disabled = false
      app_insights_internet_ingestion_enabled            = true
      app_insights_internet_query_enabled                = true
      app_insights_local_authentication_disabled         = true
      app_insights_sampling_percentage                   = 100

      # Site Configuration
      site_config = {
        always_on              = true
        minimum_tls_version    = "1.3"
        vnet_route_all_enabled = true
        use_32_bit_worker      = false
        worker_count           = 1
        cors = {
          allowed_origins = ["https://portal.azure.com"]
        }
        application_stack = {
          current_stack               = "dotnet"
          dotnet_version              = "v8.0"
          use_dotnet_isolated_runtime = true
        }
      }
    }
  ]
}


