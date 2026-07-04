locals {
  rg = provider::azurerm::parse_resource_id(var.resource_group_id)

  # Apps that reference no plan get their own dedicated B1 plan.
  auto_plan_apps = { for k, a in var.web_apps : k => a if a.service_plan_key == null && a.service_plan_id == null }

  # One user-assigned identity per app unless the caller opts out or brings their own.
  uai_apps = { for k, a in var.web_apps : k => a if a.create_user_assigned_identity }

  # Null means no identity at all (create_user_assigned_identity false with no identity block);
  # the resource's identity block is dynamic on this.
  identity_blocks = {
    for k, a in var.web_apps : k => (
      a.identity != null ? a.identity :
      a.create_user_assigned_identity ? {
        type         = "SystemAssigned, UserAssigned"
        identity_ids = [azurerm_user_assigned_identity.this[k].id]
      } : null
    )
  }

  app_insights_settings = {
    for k, a in var.web_apps : k => merge(
      a.app_insights_connection_string != null ? { APPLICATIONINSIGHTS_CONNECTION_STRING = a.app_insights_connection_string } : {},
      a.app_insights_connection_string != null && a.create_user_assigned_identity ? {
        APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "ClientId=${azurerm_user_assigned_identity.this[k].client_id};Authorization=AAD"
      } : {},
    )
  }

  effective_app_settings = {
    for k, a in var.web_apps : k => merge(
      local.app_insights_settings[k],
      a.app_settings,
    )
  }

}

resource "azurerm_service_plan" "this" {
  for_each = var.service_plans

  resource_group_name = local.rg.resource_group_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))

  name                         = each.key
  os_type                      = each.value.os_type
  sku_name                     = each.value.sku_name
  app_service_environment_id   = each.value.app_service_environment_id
  maximum_elastic_worker_count = each.value.maximum_elastic_worker_count
  per_site_scaling_enabled     = each.value.per_site_scaling_enabled
  worker_count                 = each.value.worker_count
  zone_balancing_enabled       = each.value.zone_balancing_enabled
}

# Dedicated B1 plans for apps that reference no plan: one call, one running app.
resource "azurerm_service_plan" "auto" {
  for_each = local.auto_plan_apps

  resource_group_name = local.rg.resource_group_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))

  name     = "asp-${each.key}"
  os_type  = "Windows"
  sku_name = "B1"
}

resource "azurerm_user_assigned_identity" "this" {
  for_each = local.uai_apps

  resource_group_name = local.rg.resource_group_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))

  name = "id-${each.key}"
}

# AAD ingestion for Application Insights when the module owns the identity and knows the AI scope.
resource "azurerm_role_assignment" "app_insights" {
  # Gated on the plan-known flag, never on the id itself: the id is usually a same-plan module
  # output, and unknown values in for_each keys fail the plan.
  for_each = { for k, a in var.web_apps : k => a if a.grant_app_insights_metrics_publisher && a.create_user_assigned_identity }

  scope                = each.value.app_insights_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.this[each.key].principal_id
}

resource "azurerm_windows_web_app" "this" {
  for_each = var.web_apps

  resource_group_name = local.rg.resource_group_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))

  name = each.key
  service_plan_id = coalesce(
    each.value.service_plan_id,
    each.value.service_plan_key != null ? azurerm_service_plan.this[coalesce(each.value.service_plan_key, "-")].id : null,
    try(azurerm_service_plan.auto[each.key].id, null),
  )

  https_only                                     = each.value.https_only
  public_network_access_enabled                  = each.value.public_network_access_enabled
  virtual_network_subnet_id                      = each.value.virtual_network_subnet_id
  virtual_network_backup_restore_enabled         = each.value.virtual_network_backup_restore_enabled
  virtual_network_image_pull_enabled             = each.value.virtual_network_image_pull_enabled
  client_affinity_enabled                        = each.value.client_affinity_enabled
  client_certificate_enabled                     = each.value.client_certificate_enabled
  client_certificate_mode                        = each.value.client_certificate_mode
  client_certificate_exclusion_paths             = each.value.client_certificate_exclusion_paths
  ftp_publish_basic_authentication_enabled       = each.value.ftp_publish_basic_authentication_enabled
  webdeploy_publish_basic_authentication_enabled = each.value.webdeploy_publish_basic_authentication_enabled
  key_vault_reference_identity_id                = each.value.key_vault_reference_identity_id
  enabled                                        = each.value.enabled

  app_settings = local.effective_app_settings[each.key]

  # Relies on the basic-auth publishing profile plus WEBSITE_RUN_FROM_PACKAGE or
  # SCM_DO_BUILD_DURING_DEPLOYMENT (a validation enforces the pairing); the AAD push after
  # apply needs none of that and is the documented default path.
  zip_deploy_file = each.value.zip_deploy_file

  dynamic "identity" {
    for_each = local.identity_blocks[each.key] != null ? [local.identity_blocks[each.key]] : []

    content {
      type         = identity.value.type
      identity_ids = try(identity.value.identity_ids, null)
    }
  }

  dynamic "logs" {
    for_each = each.value.logs != null ? [each.value.logs] : []

    content {
      detailed_error_messages = logs.value.detailed_error_messages
      failed_request_tracing  = logs.value.failed_request_tracing

      dynamic "application_logs" {
        for_each = logs.value.application_logs != null ? [logs.value.application_logs] : []

        content {
          file_system_level = application_logs.value.file_system_level

          dynamic "azure_blob_storage" {
            for_each = application_logs.value.azure_blob_storage != null ? [application_logs.value.azure_blob_storage] : []

            content {
              level             = azure_blob_storage.value.level
              retention_in_days = azure_blob_storage.value.retention_in_days
              sas_url           = azure_blob_storage.value.sas_url
            }
          }
        }
      }

      dynamic "http_logs" {
        for_each = logs.value.http_logs != null ? [logs.value.http_logs] : []

        content {
          dynamic "azure_blob_storage" {
            for_each = http_logs.value.azure_blob_storage != null ? [http_logs.value.azure_blob_storage] : []

            content {
              retention_in_days = azure_blob_storage.value.retention_in_days
              sas_url           = azure_blob_storage.value.sas_url
            }
          }

          dynamic "file_system" {
            for_each = http_logs.value.file_system != null ? [http_logs.value.file_system] : []

            content {
              retention_in_days = file_system.value.retention_in_days
              retention_in_mb   = file_system.value.retention_in_mb
            }
          }
        }
      }
    }
  }

  dynamic "connection_string" {
    for_each = each.value.connection_strings

    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  dynamic "sticky_settings" {
    for_each = each.value.sticky_settings != null ? [each.value.sticky_settings] : []

    content {
      app_setting_names       = sticky_settings.value.app_setting_names
      connection_string_names = sticky_settings.value.connection_string_names
    }
  }

  dynamic "storage_account" {
    for_each = each.value.storage_account_mounts

    content {
      name         = storage_account.value.name
      account_name = storage_account.value.account_name
      access_key   = storage_account.value.access_key
      share_name   = storage_account.value.share_name
      type         = storage_account.value.type
      mount_path   = storage_account.value.mount_path
    }
  }

  dynamic "backup" {
    for_each = each.value.backup != null ? [each.value.backup] : []

    content {
      name                = backup.value.name
      storage_account_url = backup.value.storage_account_url
      enabled             = backup.value.enabled

      schedule {
        frequency_interval       = backup.value.schedule.frequency_interval
        frequency_unit           = backup.value.schedule.frequency_unit
        keep_at_least_one_backup = backup.value.schedule.keep_at_least_one_backup
        retention_period_days    = backup.value.schedule.retention_period_days
        start_time               = backup.value.schedule.start_time
      }
    }
  }

  site_config {
    always_on                                     = each.value.site_config.always_on
    api_definition_url                            = each.value.site_config.api_definition_url
    api_management_api_id                         = each.value.site_config.api_management_api_id
    app_command_line                              = each.value.site_config.app_command_line
    container_registry_managed_identity_client_id = each.value.site_config.container_registry_managed_identity_client_id
    container_registry_use_managed_identity       = each.value.site_config.container_registry_use_managed_identity
    default_documents                             = each.value.site_config.default_documents
    ftps_state                                    = coalesce(each.value.site_config.ftps_state, "Disabled")
    health_check_eviction_time_in_min             = each.value.site_config.health_check_eviction_time_in_min
    health_check_path                             = each.value.site_config.health_check_path
    http2_enabled                                 = each.value.site_config.http2_enabled
    ip_restriction_default_action                 = each.value.site_config.ip_restriction_default_action
    load_balancing_mode                           = each.value.site_config.load_balancing_mode
    local_mysql_enabled                           = each.value.site_config.local_mysql_enabled
    managed_pipeline_mode                         = each.value.site_config.managed_pipeline_mode
    minimum_tls_cipher_suite                      = each.value.site_config.minimum_tls_cipher_suite
    minimum_tls_version                           = coalesce(each.value.site_config.minimum_tls_version, "1.2")
    remote_debugging_enabled                      = each.value.site_config.remote_debugging_enabled
    remote_debugging_version                      = each.value.site_config.remote_debugging_version
    scm_ip_restriction_default_action             = each.value.site_config.scm_ip_restriction_default_action
    scm_minimum_tls_version                       = each.value.site_config.scm_minimum_tls_version
    scm_use_main_ip_restriction                   = each.value.site_config.scm_use_main_ip_restriction
    use_32_bit_worker                             = each.value.site_config.use_32_bit_worker
    vnet_route_all_enabled                        = each.value.site_config.vnet_route_all_enabled
    websockets_enabled                            = each.value.site_config.websockets_enabled
    worker_count                                  = each.value.site_config.worker_count

    dynamic "application_stack" {
      for_each = each.value.site_config.application_stack != null ? [each.value.site_config.application_stack] : []

      content {
        current_stack                = application_stack.value.current_stack
        docker_image_name            = application_stack.value.docker_image_name
        docker_registry_url          = application_stack.value.docker_registry_url
        docker_registry_username     = application_stack.value.docker_registry_username
        docker_registry_password     = application_stack.value.docker_registry_password
        dotnet_version               = application_stack.value.dotnet_version
        dotnet_core_version          = application_stack.value.dotnet_core_version
        java_version                 = application_stack.value.java_version
        java_container               = application_stack.value.java_container
        java_container_version       = application_stack.value.java_container_version
        java_embedded_server_enabled = application_stack.value.java_embedded_server_enabled
        tomcat_version               = application_stack.value.tomcat_version
        node_version                 = application_stack.value.node_version
        php_version                  = application_stack.value.php_version
        python                       = application_stack.value.python
      }
    }

    dynamic "auto_heal_setting" {
      for_each = each.value.site_config.auto_heal_setting != null ? [each.value.site_config.auto_heal_setting] : []

      content {
        dynamic "action" {
          for_each = auto_heal_setting.value.action != null ? [auto_heal_setting.value.action] : []

          content {
            action_type                    = action.value.action_type
            minimum_process_execution_time = action.value.minimum_process_execution_time
          }
        }

        dynamic "trigger" {
          for_each = auto_heal_setting.value.trigger != null ? [auto_heal_setting.value.trigger] : []

          content {
            private_memory_kb = trigger.value.private_memory_kb

            dynamic "requests" {
              for_each = trigger.value.requests != null ? [trigger.value.requests] : []

              content {
                count    = requests.value.count
                interval = requests.value.interval
              }
            }

            dynamic "slow_request" {
              for_each = trigger.value.slow_request != null ? [trigger.value.slow_request] : []

              content {
                count      = slow_request.value.count
                interval   = slow_request.value.interval
                time_taken = slow_request.value.time_taken
              }
            }

            dynamic "slow_request_with_path" {
              for_each = trigger.value.slow_request_with_path

              content {
                count      = slow_request_with_path.value.count
                interval   = slow_request_with_path.value.interval
                time_taken = slow_request_with_path.value.time_taken
                path       = slow_request_with_path.value.path
              }
            }

            dynamic "status_code" {
              for_each = trigger.value.status_code

              content {
                count             = status_code.value.count
                interval          = status_code.value.interval
                status_code_range = status_code.value.status_code_range
                path              = status_code.value.path
                sub_status        = status_code.value.sub_status
                win32_status_code = status_code.value.win32_status_code
              }
            }
          }
        }
      }
    }

    dynamic "handler_mapping" {
      for_each = each.value.site_config.handler_mappings

      content {
        extension             = handler_mapping.value.extension
        script_processor_path = handler_mapping.value.script_processor_path
        arguments             = handler_mapping.value.arguments
      }
    }

    dynamic "virtual_application" {
      for_each = each.value.site_config.virtual_applications

      content {
        physical_path = virtual_application.value.physical_path
        preload       = virtual_application.value.preload
        virtual_path  = virtual_application.value.virtual_path

        dynamic "virtual_directory" {
          for_each = virtual_application.value.virtual_directories

          content {
            physical_path = virtual_directory.value.physical_path
            virtual_path  = virtual_directory.value.virtual_path
          }
        }
      }
    }

    dynamic "cors" {
      for_each = each.value.site_config.cors != null ? [each.value.site_config.cors] : []

      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }

    dynamic "ip_restriction" {
      for_each = each.value.site_config.ip_restrictions

      content {
        action                    = ip_restriction.value.action
        description               = ip_restriction.value.description
        ip_address                = ip_restriction.value.ip_address
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id

        dynamic "headers" {
          for_each = coalesce(ip_restriction.value.headers, [])

          content {
            x_azure_fdid      = headers.value.x_azure_fdid
            x_fd_health_probe = headers.value.x_fd_health_probe
            x_forwarded_for   = headers.value.x_forwarded_for
            x_forwarded_host  = headers.value.x_forwarded_host
          }
        }
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = each.value.site_config.scm_ip_restrictions

      content {
        action                    = scm_ip_restriction.value.action
        description               = scm_ip_restriction.value.description
        ip_address                = scm_ip_restriction.value.ip_address
        name                      = scm_ip_restriction.value.name
        priority                  = scm_ip_restriction.value.priority
        service_tag               = scm_ip_restriction.value.service_tag
        virtual_network_subnet_id = scm_ip_restriction.value.virtual_network_subnet_id

        dynamic "headers" {
          for_each = coalesce(scm_ip_restriction.value.headers, [])

          content {
            x_azure_fdid      = headers.value.x_azure_fdid
            x_fd_health_probe = headers.value.x_fd_health_probe
            x_forwarded_for   = headers.value.x_forwarded_for
            x_forwarded_host  = headers.value.x_forwarded_host
          }
        }
      }
    }
  }

  dynamic "auth_settings" {
    for_each = each.value.auth_settings != null ? [each.value.auth_settings] : []

    content {
      enabled                        = auth_settings.value.enabled
      additional_login_parameters    = auth_settings.value.additional_login_parameters
      allowed_external_redirect_urls = auth_settings.value.allowed_external_redirect_urls
      default_provider               = auth_settings.value.default_provider
      issuer                         = auth_settings.value.issuer
      runtime_version                = auth_settings.value.runtime_version
      token_refresh_extension_hours  = auth_settings.value.token_refresh_extension_hours
      token_store_enabled            = auth_settings.value.token_store_enabled
      unauthenticated_client_action  = auth_settings.value.unauthenticated_client_action

      dynamic "active_directory" {
        for_each = auth_settings.value.active_directory != null ? [auth_settings.value.active_directory] : []

        content {
          client_id                  = active_directory.value.client_id
          allowed_audiences          = active_directory.value.allowed_audiences
          client_secret              = active_directory.value.client_secret
          client_secret_setting_name = active_directory.value.client_secret_setting_name
        }
      }

      dynamic "facebook" {
        for_each = auth_settings.value.facebook != null ? [auth_settings.value.facebook] : []

        content {
          app_id                  = facebook.value.app_id
          app_secret              = facebook.value.app_secret
          app_secret_setting_name = facebook.value.app_secret_setting_name
          oauth_scopes            = facebook.value.oauth_scopes
        }
      }

      dynamic "github" {
        for_each = auth_settings.value.github != null ? [auth_settings.value.github] : []

        content {
          client_id                  = github.value.client_id
          client_secret              = github.value.client_secret
          client_secret_setting_name = github.value.client_secret_setting_name
          oauth_scopes               = github.value.oauth_scopes
        }
      }

      dynamic "google" {
        for_each = auth_settings.value.google != null ? [auth_settings.value.google] : []

        content {
          client_id                  = google.value.client_id
          client_secret              = google.value.client_secret
          client_secret_setting_name = google.value.client_secret_setting_name
          oauth_scopes               = google.value.oauth_scopes
        }
      }

      dynamic "microsoft" {
        for_each = auth_settings.value.microsoft != null ? [auth_settings.value.microsoft] : []

        content {
          client_id                  = microsoft.value.client_id
          client_secret              = microsoft.value.client_secret
          client_secret_setting_name = microsoft.value.client_secret_setting_name
          oauth_scopes               = microsoft.value.oauth_scopes
        }
      }

      dynamic "twitter" {
        for_each = auth_settings.value.twitter != null ? [auth_settings.value.twitter] : []

        content {
          consumer_key                 = twitter.value.consumer_key
          consumer_secret              = twitter.value.consumer_secret
          consumer_secret_setting_name = twitter.value.consumer_secret_setting_name
        }
      }
    }
  }

  dynamic "auth_settings_v2" {
    for_each = each.value.auth_settings_v2 != null ? [each.value.auth_settings_v2] : []

    content {
      auth_enabled                            = auth_settings_v2.value.auth_enabled
      config_file_path                        = auth_settings_v2.value.config_file_path
      default_provider                        = auth_settings_v2.value.default_provider
      excluded_paths                          = auth_settings_v2.value.excluded_paths
      forward_proxy_convention                = auth_settings_v2.value.forward_proxy_convention
      forward_proxy_custom_host_header_name   = auth_settings_v2.value.forward_proxy_custom_host_header_name
      forward_proxy_custom_scheme_header_name = auth_settings_v2.value.forward_proxy_custom_scheme_header_name
      http_route_api_prefix                   = auth_settings_v2.value.http_route_api_prefix
      require_authentication                  = auth_settings_v2.value.require_authentication
      require_https                           = auth_settings_v2.value.require_https
      runtime_version                         = auth_settings_v2.value.runtime_version
      unauthenticated_action                  = auth_settings_v2.value.unauthenticated_action

      dynamic "active_directory_v2" {
        for_each = auth_settings_v2.value.active_directory_v2 != null ? [auth_settings_v2.value.active_directory_v2] : []

        content {
          client_id                            = active_directory_v2.value.client_id
          tenant_auth_endpoint                 = active_directory_v2.value.tenant_auth_endpoint
          allowed_applications                 = active_directory_v2.value.allowed_applications
          allowed_audiences                    = active_directory_v2.value.allowed_audiences
          allowed_groups                       = active_directory_v2.value.allowed_groups
          allowed_identities                   = active_directory_v2.value.allowed_identities
          client_secret_certificate_thumbprint = active_directory_v2.value.client_secret_certificate_thumbprint
          client_secret_setting_name           = active_directory_v2.value.client_secret_setting_name
          jwt_allowed_client_applications      = active_directory_v2.value.jwt_allowed_client_applications
          jwt_allowed_groups                   = active_directory_v2.value.jwt_allowed_groups
          login_parameters                     = active_directory_v2.value.login_parameters
          www_authentication_disabled          = active_directory_v2.value.www_authentication_disabled
        }
      }

      dynamic "apple_v2" {
        for_each = auth_settings_v2.value.apple_v2 != null ? [auth_settings_v2.value.apple_v2] : []

        content {
          client_id                  = apple_v2.value.client_id
          client_secret_setting_name = apple_v2.value.client_secret_setting_name
        }
      }

      dynamic "azure_static_web_app_v2" {
        for_each = auth_settings_v2.value.azure_static_web_app_v2 != null ? [auth_settings_v2.value.azure_static_web_app_v2] : []

        content {
          client_id = azure_static_web_app_v2.value.client_id
        }
      }

      dynamic "custom_oidc_v2" {
        for_each = auth_settings_v2.value.custom_oidc_v2

        content {
          client_id                     = custom_oidc_v2.value.client_id
          name                          = custom_oidc_v2.value.name
          openid_configuration_endpoint = custom_oidc_v2.value.openid_configuration_endpoint
          name_claim_type               = custom_oidc_v2.value.name_claim_type
          scopes                        = custom_oidc_v2.value.scopes
        }
      }

      dynamic "facebook_v2" {
        for_each = auth_settings_v2.value.facebook_v2 != null ? [auth_settings_v2.value.facebook_v2] : []

        content {
          app_id                  = facebook_v2.value.app_id
          app_secret_setting_name = facebook_v2.value.app_secret_setting_name
          graph_api_version       = facebook_v2.value.graph_api_version
          login_scopes            = facebook_v2.value.login_scopes
        }
      }

      dynamic "github_v2" {
        for_each = auth_settings_v2.value.github_v2 != null ? [auth_settings_v2.value.github_v2] : []

        content {
          client_id                  = github_v2.value.client_id
          client_secret_setting_name = github_v2.value.client_secret_setting_name
          login_scopes               = github_v2.value.login_scopes
        }
      }

      dynamic "google_v2" {
        for_each = auth_settings_v2.value.google_v2 != null ? [auth_settings_v2.value.google_v2] : []

        content {
          client_id                  = google_v2.value.client_id
          client_secret_setting_name = google_v2.value.client_secret_setting_name
          allowed_audiences          = google_v2.value.allowed_audiences
          login_scopes               = google_v2.value.login_scopes
        }
      }

      dynamic "microsoft_v2" {
        for_each = auth_settings_v2.value.microsoft_v2 != null ? [auth_settings_v2.value.microsoft_v2] : []

        content {
          client_id                  = microsoft_v2.value.client_id
          client_secret_setting_name = microsoft_v2.value.client_secret_setting_name
          allowed_audiences          = microsoft_v2.value.allowed_audiences
          login_scopes               = microsoft_v2.value.login_scopes
        }
      }

      dynamic "twitter_v2" {
        for_each = auth_settings_v2.value.twitter_v2 != null ? [auth_settings_v2.value.twitter_v2] : []

        content {
          consumer_key                 = twitter_v2.value.consumer_key
          consumer_secret_setting_name = twitter_v2.value.consumer_secret_setting_name
        }
      }

      login {
        allowed_external_redirect_urls    = auth_settings_v2.value.login.allowed_external_redirect_urls
        cookie_expiration_convention      = auth_settings_v2.value.login.cookie_expiration_convention
        cookie_expiration_time            = auth_settings_v2.value.login.cookie_expiration_time
        logout_endpoint                   = auth_settings_v2.value.login.logout_endpoint
        nonce_expiration_time             = auth_settings_v2.value.login.nonce_expiration_time
        preserve_url_fragments_for_logins = auth_settings_v2.value.login.preserve_url_fragments_for_logins
        token_refresh_extension_time      = auth_settings_v2.value.login.token_refresh_extension_time
        token_store_enabled               = auth_settings_v2.value.login.token_store_enabled
        token_store_path                  = auth_settings_v2.value.login.token_store_path
        token_store_sas_setting_name      = auth_settings_v2.value.login.token_store_sas_setting_name
        validate_nonce                    = auth_settings_v2.value.login.validate_nonce
      }
    }
  }

}
