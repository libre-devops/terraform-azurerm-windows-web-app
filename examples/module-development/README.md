```hcl
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


```
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.4.0 |
| <a name="provider_http"></a> [http](#provider\_http) | 3.4.5 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.6.3 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_law"></a> [law](#module\_law) | libre-devops/log-analytics-workspace/azurerm | n/a |
| <a name="module_network"></a> [network](#module\_network) | libre-devops/network/azurerm | n/a |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | n/a |
| <a name="module_role_assignments"></a> [role\_assignments](#module\_role\_assignments) | github.com/libre-devops/terraform-azurerm-role-assignment | n/a |
| <a name="module_shared_vars"></a> [shared\_vars](#module\_shared\_vars) | libre-devops/shared-vars/azurerm | n/a |
| <a name="module_subnet_calculator"></a> [subnet\_calculator](#module\_subnet\_calculator) | libre-devops/subnet-calculator/null | n/a |
| <a name="module_windows_web_app"></a> [windows\_web\_app](#module\_windows\_web\_app) | ../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_user_assigned_identity.uid](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [random_string.entropy](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [azurerm_client_config.current_creds](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_key_vault.mgmt_kv](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault) | data source |
| [azurerm_resource_group.mgmt_rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_ssh_public_key.mgmt_ssh_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/ssh_public_key) | data source |
| [azurerm_user_assigned_identity.mgmt_user_assigned_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/user_assigned_identity) | data source |
| [http_http.user_ip](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_Regions"></a> [Regions](#input\_Regions) | Converts shorthand name to longhand name via lookup on map list | `map(string)` | <pre>{<br>  "eus": "East US",<br>  "euw": "West Europe",<br>  "uks": "UK South",<br>  "ukw": "UK West"<br>}</pre> | no |
| <a name="input_env"></a> [env](#input\_env) | This is passed as an environment variable, it is for the shorthand environment tag for resource.  For example, production = prod | `string` | `"prd"` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | The shorthand name of the Azure location, for example, for UK South, use uks.  For UK West, use ukw. Normally passed as TF\_VAR in pipeline | `string` | `"uks"` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of this resource | `string` | `"tst"` | no |
| <a name="input_short"></a> [short](#input\_short) | This is passed as an environment variable, it is for a shorthand name for the environment, for example hello-world = hw | `string` | `"lbd"` | no |
| <a name="input_static_tags"></a> [static\_tags](#input\_static\_tags) | The tags variable | `map(string)` | <pre>{<br>  "Contact": "info@cyber.scot",<br>  "CostCentre": "671888",<br>  "ManagedBy": "Terraform"<br>}</pre> | no |

## Outputs

No outputs.
