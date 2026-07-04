<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform Azure Windows Web App

Terraform module for Azure Windows web apps on App Service plans (dedicated B/S/P, App Service
Environments), in the Libre DevOps style: fast to get going, secure by default, flexible when
it matters.

[![CI](https://github.com/libre-devops/terraform-azurerm-windows-web-app/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azurerm-windows-web-app/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azurerm-windows-web-app?sort=semver&label=release)](https://github.com/libre-devops/terraform-azurerm-windows-web-app/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azurerm-windows-web-app)](./LICENSE)

---

## Overview

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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.80.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_role_assignment.app_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_service_plan.auto](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/service_plan) | resource |
| [azurerm_service_plan.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/service_plan) | resource |
| [azurerm_user_assigned_identity.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_windows_web_app.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/windows_web_app) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_location"></a> [location](#input\_location) | Azure region for all resources in this module. | `string` | n/a | yes |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Id of the resource group the apps live in; the module parses the name from it. | `string` | n/a | yes |
| <a name="input_service_plans"></a> [service\_plans](#input\_service\_plans) | App service plans keyed by name, shareable by multiple apps via service\_plan\_key. sku\_name<br/>defaults to B1; anything the platform supports is accepted (S/P dedicated, and so on).<br/>app\_service\_environment\_id places the plan on an App Service Environment. Apps that<br/>reference no plan get their own dedicated B1 plan automatically. | <pre>map(object({<br/>    os_type                      = optional(string, "Windows")<br/>    sku_name                     = optional(string, "B1")<br/>    app_service_environment_id   = optional(string)<br/>    maximum_elastic_worker_count = optional(number)<br/>    per_site_scaling_enabled     = optional(bool)<br/>    worker_count                 = optional(number)<br/>    zone_balancing_enabled       = optional(bool)<br/>    tags                         = optional(map(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all resources; per-app and per-plan tags override these. | `map(string)` | `{}` | no |
| <a name="input_web_apps"></a> [web\_apps](#input\_web\_apps) | Windows web apps keyed by name. Fast to get going: an entry with just an application\_stack<br/>runtime gets a dedicated B1 plan and a user-assigned identity, with secure defaults the<br/>provider does not give you (https\_only on, FTP and WebDeploy basic auth off, ftps\_state<br/>Disabled, minimum\_tls\_version floored at 1.2). Flexible when it matters: every default has an<br/>explicit override, and the full provider surface is here<br/>(application\_stack including docker, auth\_settings and auth\_settings\_v2, logs, auto\_heal,<br/>backup, mounts, sticky settings, IP restrictions, VNet integration).<br/><br/>PLAN: exactly one of service\_plan\_key (a plan from service\_plans), service\_plan\_id (bring<br/>your own), or neither (dedicated B1 plan created).<br/><br/>IDENTITY: the module creates a user-assigned identity per app by default<br/>(create\_user\_assigned\_identity), attached as "SystemAssigned, UserAssigned" so both kinds<br/>are live. Pass identity to bring your own of any type, or set<br/>create\_user\_assigned\_identity = false with no identity block for an identity-less app.<br/><br/>DEPLOY: zip\_deploy\_file relies on the basic-auth publishing profile this module disables by<br/>default, so using it requires webdeploy\_publish\_basic\_authentication\_enabled = true plus<br/>WEBSITE\_RUN\_FROM\_PACKAGE or SCM\_DO\_BUILD\_DURING\_DEPLOYMENT in app\_settings (a validation<br/>enforces the pairing); the AAD path (az webapp deployment source config-zip after apply)<br/>works with basic auth off and is what this repo's CI demonstrates.<br/><br/>APP INSIGHTS: pass app\_insights\_connection\_string to wire the app setting; with an<br/>app\_insights\_id and a module-created identity the AAD ingestion auth string and Monitoring<br/>Metrics Publisher grant are wired too. | <pre>map(object({<br/>    service_plan_key = optional(string)<br/>    service_plan_id  = optional(string)<br/><br/>    # Identity.<br/>    create_user_assigned_identity = optional(bool, true)<br/>    identity = optional(object({<br/>      type         = string<br/>      identity_ids = optional(list(string))<br/>    }))<br/>    key_vault_reference_identity_id = optional(string)<br/><br/>    # Observability. The grant flag exists because the AI id is usually a same-plan module<br/>    # output (unknown until apply), and for_each keys must stay plan-known: set it alongside<br/>    # app_insights_id to grant Monitoring Metrics Publisher to the module-created identity.<br/>    app_insights_connection_string       = optional(string)<br/>    app_insights_id                      = optional(string)<br/>    grant_app_insights_metrics_publisher = optional(bool, false)<br/><br/>    # Security and networking.<br/>    https_only                                     = optional(bool, true)<br/>    public_network_access_enabled                  = optional(bool, true)<br/>    virtual_network_subnet_id                      = optional(string)<br/>    virtual_network_backup_restore_enabled         = optional(bool)<br/>    virtual_network_image_pull_enabled             = optional(bool)<br/>    client_affinity_enabled                        = optional(bool)<br/>    client_certificate_enabled                     = optional(bool)<br/>    client_certificate_mode                        = optional(string)<br/>    client_certificate_exclusion_paths             = optional(string)<br/>    ftp_publish_basic_authentication_enabled       = optional(bool, false)<br/>    webdeploy_publish_basic_authentication_enabled = optional(bool, false)<br/>    enabled                                        = optional(bool, true)<br/><br/>    # Deployment (see description).<br/>    zip_deploy_file = optional(string)<br/><br/>    # Settings.<br/>    app_settings = optional(map(string), {})<br/>    connection_strings = optional(list(object({<br/>      name  = string<br/>      type  = string<br/>      value = string<br/>    })), [])<br/>    sticky_settings = optional(object({<br/>      app_setting_names       = optional(list(string))<br/>      connection_string_names = optional(list(string))<br/>    }))<br/><br/>    # Azure Files / Blob mounts.<br/>    storage_account_mounts = optional(list(object({<br/>      name         = string<br/>      account_name = string<br/>      access_key   = string<br/>      share_name   = string<br/>      type         = string<br/>      mount_path   = optional(string)<br/>    })), [])<br/><br/>    backup = optional(object({<br/>      name                = string<br/>      storage_account_url = string<br/>      enabled             = optional(bool, true)<br/>      schedule = object({<br/>        frequency_interval       = number<br/>        frequency_unit           = string<br/>        keep_at_least_one_backup = optional(bool)<br/>        retention_period_days    = optional(number)<br/>        start_time               = optional(string)<br/>      })<br/>    }))<br/><br/>    logs = optional(object({<br/>      detailed_error_messages = optional(bool)<br/>      failed_request_tracing  = optional(bool)<br/>      application_logs = optional(object({<br/>        file_system_level = string<br/>        azure_blob_storage = optional(object({<br/>          level             = string<br/>          retention_in_days = number<br/>          sas_url           = string<br/>        }))<br/>      }))<br/>      http_logs = optional(object({<br/>        azure_blob_storage = optional(object({<br/>          retention_in_days = optional(number)<br/>          sas_url           = string<br/>        }))<br/>        file_system = optional(object({<br/>          retention_in_days = number<br/>          retention_in_mb   = number<br/>        }))<br/>      }))<br/>    }))<br/><br/>    site_config = optional(object({<br/>      always_on                                     = optional(bool)<br/>      api_definition_url                            = optional(string)<br/>      api_management_api_id                         = optional(string)<br/>      app_command_line                              = optional(string)<br/>      container_registry_managed_identity_client_id = optional(string)<br/>      container_registry_use_managed_identity       = optional(bool)<br/>      default_documents                             = optional(list(string))<br/>      ftps_state                                    = optional(string)<br/>      health_check_eviction_time_in_min             = optional(number)<br/>      health_check_path                             = optional(string)<br/>      http2_enabled                                 = optional(bool)<br/>      ip_restriction_default_action                 = optional(string)<br/>      load_balancing_mode                           = optional(string)<br/>      local_mysql_enabled                           = optional(bool)<br/>      managed_pipeline_mode                         = optional(string)<br/>      minimum_tls_cipher_suite                      = optional(string)<br/>      minimum_tls_version                           = optional(string)<br/>      remote_debugging_enabled                      = optional(bool)<br/>      remote_debugging_version                      = optional(string)<br/>      scm_ip_restriction_default_action             = optional(string)<br/>      scm_minimum_tls_version                       = optional(string)<br/>      scm_use_main_ip_restriction                   = optional(bool)<br/>      use_32_bit_worker                             = optional(bool)<br/>      vnet_route_all_enabled                        = optional(bool)<br/>      websockets_enabled                            = optional(bool)<br/>      worker_count                                  = optional(number)<br/><br/>      application_stack = optional(object({<br/>        current_stack                = optional(string)<br/>        docker_image_name            = optional(string)<br/>        docker_registry_url          = optional(string)<br/>        docker_registry_username     = optional(string)<br/>        docker_registry_password     = optional(string)<br/>        dotnet_version               = optional(string)<br/>        dotnet_core_version          = optional(string)<br/>        java_version                 = optional(string)<br/>        java_container               = optional(string)<br/>        java_container_version       = optional(string)<br/>        java_embedded_server_enabled = optional(bool)<br/>        tomcat_version               = optional(string)<br/>        node_version                 = optional(string)<br/>        php_version                  = optional(string)<br/>        python                       = optional(bool)<br/>      }))<br/><br/>      handler_mappings = optional(list(object({<br/>        extension             = string<br/>        script_processor_path = string<br/>        arguments             = optional(string)<br/>      })), [])<br/><br/>      virtual_applications = optional(list(object({<br/>        physical_path = string<br/>        preload       = bool<br/>        virtual_path  = string<br/>        virtual_directories = optional(list(object({<br/>          physical_path = optional(string)<br/>          virtual_path  = optional(string)<br/>        })), [])<br/>      })), [])<br/><br/>      auto_heal_setting = optional(object({<br/>        action = optional(object({<br/>          action_type                    = string<br/>          minimum_process_execution_time = optional(string)<br/>        }))<br/>        trigger = optional(object({<br/>          private_memory_kb = optional(number)<br/>          requests = optional(object({<br/>            count    = number<br/>            interval = string<br/>          }))<br/>          slow_request = optional(object({<br/>            count      = number<br/>            interval   = string<br/>            time_taken = string<br/>          }))<br/>          slow_request_with_path = optional(list(object({<br/>            count      = number<br/>            interval   = string<br/>            time_taken = string<br/>            path       = optional(string)<br/>          })), [])<br/>          status_code = optional(list(object({<br/>            count             = number<br/>            interval          = string<br/>            status_code_range = string<br/>            path              = optional(string)<br/>            sub_status        = optional(number)<br/>            win32_status_code = optional(number)<br/>          })), [])<br/>        }))<br/>      }))<br/><br/>      cors = optional(object({<br/>        allowed_origins     = optional(list(string))<br/>        support_credentials = optional(bool)<br/>      }))<br/><br/>      ip_restrictions = optional(list(object({<br/>        action                    = optional(string)<br/>        description               = optional(string)<br/>        ip_address                = optional(string)<br/>        name                      = optional(string)<br/>        priority                  = optional(number)<br/>        service_tag               = optional(string)<br/>        virtual_network_subnet_id = optional(string)<br/>        headers = optional(list(object({<br/>          x_azure_fdid      = optional(list(string))<br/>          x_fd_health_probe = optional(list(string))<br/>          x_forwarded_for   = optional(list(string))<br/>          x_forwarded_host  = optional(list(string))<br/>        })))<br/>      })), [])<br/><br/>      scm_ip_restrictions = optional(list(object({<br/>        action                    = optional(string)<br/>        description               = optional(string)<br/>        ip_address                = optional(string)<br/>        name                      = optional(string)<br/>        priority                  = optional(number)<br/>        service_tag               = optional(string)<br/>        virtual_network_subnet_id = optional(string)<br/>        headers = optional(list(object({<br/>          x_azure_fdid      = optional(list(string))<br/>          x_fd_health_probe = optional(list(string))<br/>          x_forwarded_for   = optional(list(string))<br/>          x_forwarded_host  = optional(list(string))<br/>        })))<br/>      })), [])<br/>    }), {})<br/><br/>    auth_settings = optional(object({<br/>      enabled                        = bool<br/>      additional_login_parameters    = optional(map(string))<br/>      allowed_external_redirect_urls = optional(list(string))<br/>      default_provider               = optional(string)<br/>      issuer                         = optional(string)<br/>      runtime_version                = optional(string)<br/>      token_refresh_extension_hours  = optional(number)<br/>      token_store_enabled            = optional(bool)<br/>      unauthenticated_client_action  = optional(string)<br/><br/>      active_directory = optional(object({<br/>        client_id                  = string<br/>        allowed_audiences          = optional(list(string))<br/>        client_secret              = optional(string)<br/>        client_secret_setting_name = optional(string)<br/>      }))<br/>      facebook = optional(object({<br/>        app_id                  = string<br/>        app_secret              = optional(string)<br/>        app_secret_setting_name = optional(string)<br/>        oauth_scopes            = optional(list(string))<br/>      }))<br/>      github = optional(object({<br/>        client_id                  = string<br/>        client_secret              = optional(string)<br/>        client_secret_setting_name = optional(string)<br/>        oauth_scopes               = optional(list(string))<br/>      }))<br/>      google = optional(object({<br/>        client_id                  = string<br/>        client_secret              = optional(string)<br/>        client_secret_setting_name = optional(string)<br/>        oauth_scopes               = optional(list(string))<br/>      }))<br/>      microsoft = optional(object({<br/>        client_id                  = string<br/>        client_secret              = optional(string)<br/>        client_secret_setting_name = optional(string)<br/>        oauth_scopes               = optional(list(string))<br/>      }))<br/>      twitter = optional(object({<br/>        consumer_key                 = string<br/>        consumer_secret              = optional(string)<br/>        consumer_secret_setting_name = optional(string)<br/>      }))<br/>    }))<br/><br/>    auth_settings_v2 = optional(object({<br/>      auth_enabled                            = optional(bool)<br/>      config_file_path                        = optional(string)<br/>      default_provider                        = optional(string)<br/>      excluded_paths                          = optional(list(string))<br/>      forward_proxy_convention                = optional(string)<br/>      forward_proxy_custom_host_header_name   = optional(string)<br/>      forward_proxy_custom_scheme_header_name = optional(string)<br/>      http_route_api_prefix                   = optional(string)<br/>      require_authentication                  = optional(bool)<br/>      require_https                           = optional(bool)<br/>      runtime_version                         = optional(string)<br/>      unauthenticated_action                  = optional(string)<br/><br/>      active_directory_v2 = optional(object({<br/>        client_id                            = string<br/>        tenant_auth_endpoint                 = string<br/>        allowed_applications                 = optional(list(string))<br/>        allowed_audiences                    = optional(list(string))<br/>        allowed_groups                       = optional(list(string))<br/>        allowed_identities                   = optional(list(string))<br/>        client_secret_certificate_thumbprint = optional(string)<br/>        client_secret_setting_name           = optional(string)<br/>        jwt_allowed_client_applications      = optional(list(string))<br/>        jwt_allowed_groups                   = optional(list(string))<br/>        login_parameters                     = optional(map(string))<br/>        www_authentication_disabled          = optional(bool)<br/>      }))<br/>      apple_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>      }))<br/>      azure_static_web_app_v2 = optional(object({<br/>        client_id = string<br/>      }))<br/>      custom_oidc_v2 = optional(list(object({<br/>        client_id                     = string<br/>        name                          = string<br/>        openid_configuration_endpoint = string<br/>        name_claim_type               = optional(string)<br/>        scopes                        = optional(list(string))<br/>      })), [])<br/>      facebook_v2 = optional(object({<br/>        app_id                  = string<br/>        app_secret_setting_name = string<br/>        graph_api_version       = optional(string)<br/>        login_scopes            = optional(list(string))<br/>      }))<br/>      github_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>        login_scopes               = optional(list(string))<br/>      }))<br/>      google_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>        allowed_audiences          = optional(list(string))<br/>        login_scopes               = optional(list(string))<br/>      }))<br/>      microsoft_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>        allowed_audiences          = optional(list(string))<br/>        login_scopes               = optional(list(string))<br/>      }))<br/>      twitter_v2 = optional(object({<br/>        consumer_key                 = string<br/>        consumer_secret_setting_name = string<br/>      }))<br/>      login = optional(object({<br/>        allowed_external_redirect_urls    = optional(list(string))<br/>        cookie_expiration_convention      = optional(string)<br/>        cookie_expiration_time            = optional(string)<br/>        logout_endpoint                   = optional(string)<br/>        nonce_expiration_time             = optional(string)<br/>        preserve_url_fragments_for_logins = optional(bool)<br/>        token_refresh_extension_time      = optional(number)<br/>        token_store_enabled               = optional(bool)<br/>        token_store_path                  = optional(string)<br/>        token_store_sas_setting_name      = optional(string)<br/>        validate_nonce                    = optional(bool)<br/>      }), {})<br/>    }))<br/><br/>    tags = optional(map(string))<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_default_hostnames"></a> [default\_hostnames](#output\_default\_hostnames) | Map of app name to default hostname. |
| <a name="output_identity_principal_ids"></a> [identity\_principal\_ids](#output\_identity\_principal\_ids) | Map of app name to { system\_assigned, user\_assigned } principal ids (nulls where an identity kind is absent). |
| <a name="output_possible_outbound_ip_address_lists"></a> [possible\_outbound\_ip\_address\_lists](#output\_possible\_outbound\_ip\_address\_lists) | Map of app name to the possible outbound IP address list. |
| <a name="output_service_plan_ids"></a> [service\_plan\_ids](#output\_service\_plan\_ids) | Map of plan name (or app name for auto-created plans) to plan id. |
| <a name="output_user_assigned_identity_ids"></a> [user\_assigned\_identity\_ids](#output\_user\_assigned\_identity\_ids) | Map of app name to the module-created user assigned identity id (only apps with create\_user\_assigned\_identity). |
| <a name="output_web_app_ids"></a> [web\_app\_ids](#output\_web\_app\_ids) | Map of app name to app id. |
| <a name="output_web_app_ids_zipmap"></a> [web\_app\_ids\_zipmap](#output\_web\_app\_ids\_zipmap) | Map of app name to { name, id } for easy composition. |
| <a name="output_web_apps"></a> [web\_apps](#output\_web\_apps) | Map of app name to the full linux web app object. Sensitive as a whole because the object carries the site credentials and custom\_domain\_verification\_id; the ids, hostnames, and identity maps alongside stay plain for composition. |
<!-- END_TF_DOCS -->
