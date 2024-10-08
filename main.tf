resource "azurerm_service_plan" "service_plan" {
  for_each            = { for app in var.windows_web_apps : app.name => app if app.create_new_app_service_plan == true }
  name                = each.value.app_service_plan_name != null ? each.value.app_service_plan_name : "asp-${each.value.name}"
  resource_group_name = each.value.rg_name
  location            = each.value.location
  os_type             = each.value.os_type != null ? each.value.os_type : "Linux"
  sku_name            = each.value.sku_name
}

resource "azurerm_windows_web_app" "web_app" {
  for_each                                       = { for app in var.windows_web_apps : app.name => app }
  name                                           = each.value.name
  service_plan_id                                = each.value.service_plan_id != null ? each.value.service_plan_id : lookup(azurerm_service_plan.service_plan, each.key, null).id
  location                                       = each.value.location
  resource_group_name                            = each.value.rg_name
  app_settings                                   = each.value.create_new_app_insights == true && lookup(local.app_insights_map, each.value.app_insights_name, null) != null ? merge(each.value.app_settings, local.app_insights_map[each.value.app_insights_name]) : each.value.app_settings
  https_only                                     = each.value.https_only
  tags                                           = each.value.tags
  client_affinity_enabled                        = each.value.client_affinity_enabled
  client_certificate_enabled                     = each.value.client_certificate_enabled
  client_certificate_mode                        = each.value.client_certificate_mode
  client_certificate_exclusion_paths             = each.value.client_certificate_exclusion_paths
  enabled                                        = each.value.enabled
  ftp_publish_basic_authentication_enabled       = each.value.ftp_publish_basic_authentication_enable
  public_network_access_enabled                  = each.value.public_network_access_enabled
  key_vault_reference_identity_id                = each.value.key_vault_reference_identity_id
  virtual_network_subnet_id                      = each.value.virtual_network_subnet_id
  webdeploy_publish_basic_authentication_enabled = each.value.webdeploy_publish_basic_authentication_enabled
  zip_deploy_file                                = each.value.zip_deploy_file


  dynamic "logs" {
    for_each = each.value.logs != null ? [each.value.logs] : []
    content {
      detailed_error_messages = logs.value.detailed_error_messages
      failed_request_tracing  = logs.value.failed_request_tracing

      dynamic "application_logs" {
        for_each = logs.value.application_logs != null ? [logs.value.application_logs] : []
        content {
          dynamic "azure_blob_storage" {
            for_each = application_logs.value.azure_blob_storage != null ? [application_logs.value.azure_blob_storage] : []
            content {
              level             = azure_blob_storage.value.level
              sas_url           = azure_blob_storage.value.sas_url
              retention_in_days = azure_blob_storage.value.retention_in_days
            }
          }
          file_system_level = application_logs.value.file_system_level
        }
      }

      dynamic "http_logs" {
        for_each = logs.value.http_logs != null ? [logs.value.http_logs] : []
        content {
          dynamic "azure_blob_storage" {
            for_each = http_logs.value.azure_blob_storage_http != null ? [http_logs.value.azure_blob_storage_http] : []
            content {
              sas_url           = azure_blob_storage_http.value.sas_url
              retention_in_days = azure_blob_storage_http.value.retention_in_days
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


  dynamic "identity" {
    for_each = each.value.identity_type == "SystemAssigned" ? [each.value.identity_type] : []
    content {
      type = each.value.identity_type
    }
  }

  dynamic "identity" {
    for_each = each.value.identity_type == "SystemAssigned, UserAssigned" ? [each.value.identity_type] : []
    content {
      type         = each.value.identity_type
      identity_ids = try(each.value.identity_ids, [])
    }
  }


  dynamic "identity" {
    for_each = each.value.identity_type == "UserAssigned" ? [each.value.identity_type] : []
    content {
      type         = each.value.identity_type
      identity_ids = length(try(each.value.identity_ids, [])) > 0 ? each.value.identity_ids : []
    }
  }

  dynamic "storage_account" {
    for_each = each.value.storage_account != null ? [each.value.storage_account] : []

    content {
      access_key   = storage_account.value.access_key
      account_name = storage_account.value.account_name
      name         = storage_account.value.name
      share_name   = storage_account.value.share_name
      type         = storage_account.value.type
      mount_path   = storage_account.value.mount_path
    }
  }


  dynamic "sticky_settings" {
    for_each = each.value.sticky_settings != null ? [each.value.sticky_settings] : []
    content {
      app_setting_names       = sticky_settings.value.app_setting_names
      connection_string_names = sticky_settings.value.connection_string_names
    }
  }

  dynamic "connection_string" {
    for_each = each.value.connection_string != null ? [each.value.connection_string] : []
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  dynamic "backup" {
    for_each = each.value.backup != null ? [each.value.backup] : []
    content {
      name                = backup.value.name
      enabled             = backup.value.enabled
      storage_account_url = try(backup.value.storage_account_url, var.backup_sas_url)

      dynamic "schedule" {
        for_each = backup.value.schedule != null ? [backup.value.schedule] : []
        content {
          frequency_interval       = schedule.value.frequency_interval
          frequency_unit           = schedule.value.frequency_unit
          keep_at_least_one_backup = schedule.value.keep_at_least_one_backup
          retention_period_days    = schedule.value.retention_period_days
          start_time               = schedule.value.start_time
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
          client_id         = active_directory.value.client_id
          client_secret     = active_directory.value.client_secret
          allowed_audiences = active_directory.value.allowed_audiences
        }
      }

      dynamic "facebook" {
        for_each = auth_settings.value.facebook != null ? [auth_settings.value.facebook] : []

        content {
          app_id       = facebook.value.app_id
          app_secret   = facebook.value.app_secret
          oauth_scopes = facebook.value.oauth_scopes
        }
      }

      dynamic "google" {
        for_each = auth_settings.value.google != null ? [auth_settings.value.google] : []

        content {
          client_id     = google.value.client_id
          client_secret = google.value.client_secret
          oauth_scopes  = google.value.oauth_scopes
        }
      }

      dynamic "microsoft" {
        for_each = auth_settings.value.microsoft != null ? [auth_settings.value.microsoft] : []

        content {
          client_id     = microsoft.value.client_id
          client_secret = microsoft.value.client_secret
          oauth_scopes  = microsoft.value.oauth_scopes
        }
      }

      dynamic "twitter" {
        for_each = auth_settings.value.twitter != null ? [auth_settings.value.twitter] : []

        content {
          consumer_key    = twitter.value.consumer_key
          consumer_secret = twitter.value.consumer_secret
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
    }
  }

  dynamic "auth_settings_v2" {
    for_each = each.value.auth_settings_v2 != null ? [each.value.auth_settings_v2] : []

    content {
      auth_enabled                            = auth_settings_v2.value.auth_enabled
      runtime_version                         = auth_settings_v2.value.runtime_version
      config_file_path                        = auth_settings_v2.value.config_file_path
      require_authentication                  = auth_settings_v2.value.require_authentication
      unauthenticated_action                  = auth_settings_v2.value.unauthenticated_action
      default_provider                        = auth_settings_v2.value.default_provider
      excluded_paths                          = toset(auth_settings_v2.value.excluded_paths)
      require_https                           = auth_settings_v2.value.require_https
      http_route_api_prefix                   = auth_settings_v2.value.http_route_api_prefix
      forward_proxy_convention                = auth_settings_v2.value.forward_proxy_convention
      forward_proxy_custom_host_header_name   = auth_settings_v2.value.forward_proxy_custom_host_header_name
      forward_proxy_custom_scheme_header_name = auth_settings_v2.value.forward_proxy_custom_scheme_header_name

      dynamic "apple_v2" {
        for_each = auth_settings_v2.value.apple_v2 != null ? [auth_settings_v2.value.apple_v2] : []

        content {
          client_id                  = apple_v2.value.client_id
          client_secret_setting_name = apple_v2.value.client_secret_setting_name
          login_scopes               = toset(apple_v2.value.login_scopes)
        }
      }

      dynamic "active_directory_v2" {
        for_each = auth_settings_v2.value.active_directory_v2 != null ? [auth_settings_v2.value.active_directory_v2] : []

        content {
          client_id                            = active_directory_v2.value.client_id
          tenant_auth_endpoint                 = active_directory_v2.value.tenant_auth_endpoint
          client_secret_setting_name           = active_directory_v2.value.client_secret_setting_name
          client_secret_certificate_thumbprint = active_directory_v2.value.client_secret_certificate_thumbprint
          jwt_allowed_groups                   = toset(active_directory_v2.value.jwt_allowed_groups)
          jwt_allowed_client_applications      = toset(active_directory_v2.value.jwt_allowed_client_applications)
          www_authentication_disabled          = active_directory_v2.value.www_authentication_disabled
          allowed_groups                       = toset(active_directory_v2.value.allowed_groups)
          allowed_identities                   = toset(active_directory_v2.value.allowed_identities)
          allowed_applications                 = toset(active_directory_v2.value.allowed_applications)
          login_parameters                     = active_directory_v2.value.login_parameters
          allowed_audiences                    = toset(active_directory_v2.value.allowed_audiences)
        }
      }

      dynamic "azure_static_web_app_v2" {
        for_each = auth_settings_v2.value.azure_static_web_app_v2 != null ? [auth_settings_v2.value.azure_static_web_app_v2] : []

        content {
          client_id = azure_static_web_app_v2.value.client_id
        }
      }

      dynamic "custom_oidc_v2" {
        for_each = auth_settings_v2.value.custom_oidc_v2 != null ? [auth_settings_v2.value.custom_oidc_v2] : []

        content {
          name                          = custom_oidc_v2.value.name
          client_id                     = custom_oidc_v2.value.client_id
          openid_configuration_endpoint = custom_oidc_v2.value.openid_configuration_endpoint
          name_claim_type               = custom_oidc_v2.value.name_claim_type
          scopes                        = toset(custom_oidc_v2.value.scopes)
          client_credential_method      = custom_oidc_v2.value.client_credential_method
          client_secret_setting_name    = custom_oidc_v2.value.client_secret_setting_name
          authorisation_endpoint        = custom_oidc_v2.value.authorisation_endpoint
          token_endpoint                = custom_oidc_v2.value.token_endpoint
          issuer_endpoint               = custom_oidc_v2.value.issuer_endpoint
          certification_uri             = custom_oidc_v2.value.certification_uri
        }
      }


      dynamic "facebook_v2" {
        for_each = auth_settings_v2.value.facebook_v2 != null ? [auth_settings_v2.value.facebook_v2] : []

        content {
          graph_api_version       = facebook_v2.value.graph_api_version
          login_scopes            = toset(facebook_v2.value.login_scopes)
          app_id                  = facebook_v2_value.app_id
          app_secret_setting_name = facebook_v2.value.app_secret_setting_name
        }
      }

      dynamic "github_v2" {
        for_each = auth_settings_v2.value.github_v2 != null ? [auth_settings_v2.value.github_v2] : []

        content {
          client_id                  = github_v2.value.client_id
          client_secret_setting_name = github_v2.value.client_secret_setting_name
          login_scopes               = toset(github_v2.value.login_scopes)
        }
      }

      dynamic "google_v2" {
        for_each = auth_settings_v2.value.google_v2 != null ? [auth_settings_v2.value.google_v2] : []

        content {
          client_id                  = google_v2.value.client_id
          client_secret_setting_name = google_v2.value.client_secret_setting_name
          allowed_audiences          = toset(google_v2.value.allowed_audiences)
          login_scopes               = toset(google_v2.value.login_scopes)
        }
      }

      dynamic "microsoft_v2" {
        for_each = auth_settings_v2.value.microsoft_v2 != null ? [auth_settings_v2.value.microsoft_v2] : []

        content {
          client_id                  = microsoft_v2.value.client_id
          client_secret_setting_name = microsoft_v2.value.client_secret_setting_name
          allowed_audiences          = toset(microsoft_v2.value.allowed_audiences)
          login_scopes               = toset(microsoft_v2.value.login_scopes)
        }
      }

      dynamic "twitter_v2" {
        for_each = auth_settings_v2.value.twitter_v2 != null ? [auth_settings_v2.value.twitter_v2] : []
        content {
          consumer_key                 = twitter_v2.value.consumer_key
          consumer_secret_setting_name = twitter_v2.value.consumer_secret_setting_name
        }
      }

      dynamic "login" {
        for_each = auth_settings_v2.value.login != null ? [auth_settings_v2.value.login] : []

        content {
          logout_endpoint                   = login.value.logout_endpoint
          token_store_enabled               = login.value.token_store_enabled
          token_refresh_extension_time      = login.value.token_refresh_extension_time
          token_store_path                  = login.value.token_store_path
          token_store_sas_setting_name      = login.value.token_store_sas_setting_name
          preserve_url_fragments_for_logins = login.value.preserve_url_fragments_for_logins
          allowed_external_redirect_urls    = toset(login.value.allowed_external_redirect_urls)
          cookie_expiration_convention      = login.value.cookie_expiration_convention
          cookie_expiration_time            = login.value.cookie_expiration_time
          validate_nonce                    = login.value.validate_nonce
          nonce_expiration_time             = login.value.nonce_expiration_time
        }
      }
    }
  }


  dynamic "site_config" {
    for_each = each.value.site_config != null ? [each.value.site_config] : []

    content {
      always_on                                     = site_config.value.always_on
      api_definition_url                            = site_config.value.api_definition_url
      api_management_api_id                         = site_config.value.api_management_api_id
      app_command_line                              = site_config.value.app_command_line
      container_registry_managed_identity_client_id = site_config.value.container_registry_managed_identity_client_id
      container_registry_use_managed_identity       = site_config.value.container_registry_use_managed_identity
      ftps_state                                    = site_config.value.ftps_state
      health_check_path                             = site_config.value.health_check_path
      health_check_eviction_time_in_min             = site_config.value.health_check_eviction_time_in_min
      http2_enabled                                 = site_config.value.http2_enabled
      load_balancing_mode                           = site_config.value.load_balancing_mode
      managed_pipeline_mode                         = site_config.value.managed_pipeline_mode
      minimum_tls_version                           = site_config.value.minimum_tls_version
      remote_debugging_enabled                      = site_config.value.remote_debugging_enabled
      remote_debugging_version                      = site_config.value.remote_debugging_version
      scm_minimum_tls_version                       = site_config.value.scm_minimum_tls_version
      scm_use_main_ip_restriction                   = site_config.value.scm_use_main_ip_restriction
      use_32_bit_worker                             = site_config.value.use_32_bit_worker
      websockets_enabled                            = site_config.value.websockets_enabled
      vnet_route_all_enabled                        = site_config.value.vnet_route_all_enabled
      worker_count                                  = site_config.value.worker_count
      default_documents                             = toset(site_config.value.default_documents)

      dynamic "auto_heal_setting" {
        for_each = site_config.value.auto_heal_setting != null ? [site_config.value.auto_heal_setting] : []
        content {

          dynamic "action" {
            for_each = auto_heal_setting.value.action != null ? [auto_heal_setting.value.action] : []
            content {
              action_type                    = action.value.action_type
              minimum_process_execution_time = action.value.minimum_process_execution_time

              dynamic "custom_action" {
                for_each = action.value.custom_action != null ? [action.value.custom_action] : []
                content {
                  executable = custom_action.value.executable
                  parameters = custom_action.value.parameters
                }
              }
            }
          }

          dynamic "trigger" {
            for_each = auto_heal_setting.value.trigger != null ? [auto_heal_setting.value.trigger] : []
            content {
              private_memory_kb = trigger.value.private_memory_kb

              dynamic "slow_request_with_path" {
                for_each = trigger.value.slow_request_with_path != null ? trigger.value.slow_request_with_path : []
                content {
                  count      = slow_request_with_path.value.count
                  time_taken = slow_request_with_path.value.time_taken
                  path       = slow_request_with_path.value.path
                  interval   = slow_request_with_path.value.interval
                }
              }

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

              dynamic "status_code" {
                for_each = trigger.value.status_code != null ? trigger.value.status_code : []
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


      dynamic "application_stack" {
        for_each = site_config.value.application_stack != null ? [site_config.value.application_stack] : []
        content {
          current_stack                = application_stack.value.current_stack
          docker_image_name            = application_stack.value.docker_image_name
          docker_registry_url          = application_stack.value.docker_registry_url
          docker_registry_username     = application_stack.value.docker_registry_username
          docker_registry_password     = application_stack.value.docker_registry_password
          dotnet_version               = application_stack.value.dotnet_version
          dotnet_core_version          = application_stack.value.dotnet_core_version
          tomcat_version               = application_stack.value.tomcat_version
          java_embedded_server_enabled = application_stack.value.java_embedded_server_enabled
          java_version                 = application_stack.value.java_version
          node_version                 = application_stack.value.node_version
          php_version                  = application_stack.value.php_version
          python                       = application_stack.value.python
        }
      }



      dynamic "cors" {
        for_each = site_config.value.cors != null ? [site_config.value.cors] : []
        content {
          allowed_origins     = cors.value.allowed_origins
          support_credentials = cors.value.support_credentials
        }
      }

      dynamic "ip_restriction" {
        for_each = site_config.value.ip_restriction != null ? [site_config.value.ip_restriction] : []

        content {
          ip_address                = ip_restriction.value.ip_address
          service_tag               = ip_restriction.value.service_tag
          virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
          name                      = ip_restriction.value.name
          priority                  = ip_restriction.value.priority
          action                    = ip_restriction.value.action

          dynamic "headers" {
            for_each = ip_restriction.value.headers != null ? [ip_restriction.value.headers] : []

            content {
              x_azure_fdid      = headers.value.x_azure_fdid
              x_fd_health_probe = headers.value.x_fd_health_prob
              x_forwarded_for   = headers.value.x_forwarded_for
              x_forwarded_host  = headers.value.x_forwarded_host
            }
          }
        }
      }

      dynamic "scm_ip_restriction" {
        for_each = site_config.value.scm_ip_restriction != null ? [site_config.value.scm_ip_restriction] : []

        content {
          ip_address                = scm_ip_restriction.value.ip_address
          service_tag               = scm_ip_restriction.value.service_tag
          virtual_network_subnet_id = scm_ip_restriction.value.virtual_network_subnet_id
          name                      = scm_ip_restriction.value.name
          priority                  = scm_ip_restriction.value.priority
          action                    = scm_ip_restriction.value.action

          dynamic "headers" {
            for_each = scm_ip_restriction.value.headers != null ? [scm_ip_restriction.value.headers] : []

            content {
              x_azure_fdid      = headers.value.x_azure_fdid
              x_fd_health_probe = headers.value.x_fd_health_prob
              x_forwarded_for   = headers.value.x_forwarded_for
              x_forwarded_host  = headers.value.x_forwarded_host
            }
          }
        }
      }
    }
  }
}