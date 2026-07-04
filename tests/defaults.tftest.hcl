# Tests for the module. azurerm is mocked (no credentials, no cloud):
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mock"
      principal_id = "00000000-0000-0000-0000-00000000aaaa"
      client_id    = "00000000-0000-0000-0000-00000000bbbb"
    }
  }

  mock_resource "azurerm_service_plan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Web/serverFarms/asp-mock"
    }
  }
}

variables {
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001"
  location          = "uksouth"
  tags              = { Environment = "tst" }
}

# One app, nothing but the runtime: dedicated B1 plan, a UAI attached both-kinds, and the
# secure defaults that override the provider's (https_only, basic auth off).
run "fast_to_get_going" {
  command = apply

  variables {
    web_apps = {
      "app-web-ldo-uks-tst-01" = {
        site_config = { application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" } }
      }
    }
  }

  assert {
    condition     = azurerm_service_plan.auto["app-web-ldo-uks-tst-01"].sku_name == "B1"
    error_message = "An app with no plan reference should get a dedicated B1 plan."
  }

  assert {
    condition     = azurerm_windows_web_app.this["app-web-ldo-uks-tst-01"].identity[0].type == "SystemAssigned, UserAssigned"
    error_message = "The module identity default should attach both kinds."
  }

  assert {
    condition     = azurerm_windows_web_app.this["app-web-ldo-uks-tst-01"].https_only == true
    error_message = "https_only should default true (the provider default is false)."
  }

  assert {
    condition     = azurerm_windows_web_app.this["app-web-ldo-uks-tst-01"].ftp_publish_basic_authentication_enabled == false && azurerm_windows_web_app.this["app-web-ldo-uks-tst-01"].webdeploy_publish_basic_authentication_enabled == false
    error_message = "Basic-auth publishing should default off (the provider default is on)."
  }
}

# Plans as a map: two apps share one plan; a third brings its own plan id.
run "plan_shapes" {
  command = apply

  variables {
    service_plans = {
      "asp-shared-ldo-uks-tst-01" = { sku_name = "P1v3" }
    }
    web_apps = {
      "app-a-ldo-uks-tst-01" = {
        service_plan_key = "asp-shared-ldo-uks-tst-01"
        site_config      = { application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" } }
      }
      "app-b-ldo-uks-tst-01" = {
        service_plan_key = "asp-shared-ldo-uks-tst-01"
        site_config      = { application_stack = { current_stack = "node", node_version = "~20" } }
      }
      "app-c-ldo-uks-tst-01" = {
        service_plan_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-x/providers/Microsoft.Web/serverFarms/asp-byo"
        site_config     = { application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" } }
      }
    }
  }

  assert {
    condition     = azurerm_service_plan.this["asp-shared-ldo-uks-tst-01"].sku_name == "P1v3"
    error_message = "The shared plan should carry its configured sku."
  }

  assert {
    condition     = length(azurerm_service_plan.auto) == 0
    error_message = "No auto plans should be created when every app references a plan."
  }

  assert {
    condition     = azurerm_windows_web_app.this["app-c-ldo-uks-tst-01"].service_plan_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-x/providers/Microsoft.Web/serverFarms/asp-byo"
    error_message = "A brought plan id should be used verbatim."
  }
}

# A docker app: the container stack passes through.
run "docker_stack" {
  command = apply

  variables {
    web_apps = {
      "app-docker-ldo-uks-tst-01" = {
        site_config = {
          application_stack = {
            docker_image_name   = "nginx:latest"
            docker_registry_url = "https://index.docker.io"
          }
        }
      }
    }
  }

  assert {
    condition     = azurerm_windows_web_app.this["app-docker-ldo-uks-tst-01"].site_config[0].application_stack[0].docker_image_name == "nginx:latest"
    error_message = "The docker image should pass through."
  }
}

# An identity-less app.
run "no_identity_at_all" {
  command = apply

  variables {
    web_apps = {
      "app-noid-ldo-uks-tst-01" = {
        create_user_assigned_identity = false
        site_config                   = { application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" } }
      }
    }
  }

  assert {
    condition     = length(azurerm_windows_web_app.this["app-noid-ldo-uks-tst-01"].identity) == 0
    error_message = "No identity block should be present when none is created or brought."
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.this) == 0
    error_message = "No user assigned identity should be created."
  }
}

# App Insights wiring: the connection string setting plus the AAD ingestion auth string and grant.
run "app_insights_wiring" {
  command = apply

  variables {
    web_apps = {
      "app-ai-ldo-uks-tst-01" = {
        app_insights_connection_string       = "InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://uksouth-1.in.applicationinsights.azure.com/"
        app_insights_id                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Insights/components/appi-mock"
        grant_app_insights_metrics_publisher = true
        site_config                          = { application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" } }
      }
    }
  }

  assert {
    condition     = azurerm_windows_web_app.this["app-ai-ldo-uks-tst-01"].app_settings["APPLICATIONINSIGHTS_AUTHENTICATION_STRING"] == "ClientId=00000000-0000-0000-0000-00000000bbbb;Authorization=AAD"
    error_message = "The AAD ingestion auth string should be wired for the module identity."
  }

  assert {
    condition     = azurerm_role_assignment.app_insights["app-ai-ldo-uks-tst-01"].role_definition_name == "Monitoring Metrics Publisher"
    error_message = "The Monitoring Metrics Publisher grant should be created."
  }
}

# The zip_deploy_file pairing validation.
run "zip_deploy_pairing_accepted" {
  command = plan

  variables {
    web_apps = {
      "app-zip-ldo-uks-tst-01" = {
        zip_deploy_file                                = "app.zip"
        webdeploy_publish_basic_authentication_enabled = true
        app_settings                                   = { SCM_DO_BUILD_DURING_DEPLOYMENT = "true" }
        site_config                                    = { application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" } }
      }
    }
  }

  assert {
    condition     = azurerm_windows_web_app.this["app-zip-ldo-uks-tst-01"].zip_deploy_file == "app.zip"
    error_message = "zip_deploy_file should pass through when correctly paired."
  }
}

run "rejects_zip_deploy_without_pairing" {
  command = plan

  variables {
    web_apps = {
      "app-badzip-ldo-uks-tst-01" = {
        zip_deploy_file = "app.zip"
        site_config     = { application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" } }
      }
    }
  }

  expect_failures = [var.web_apps]
}

run "rejects_two_plan_references" {
  command = plan

  variables {
    service_plans = { "asp-x-ldo-uks-tst-01" = {} }
    web_apps = {
      "app-bad-ldo-uks-tst-01" = {
        service_plan_key = "asp-x-ldo-uks-tst-01"
        service_plan_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-x/providers/Microsoft.Web/serverFarms/asp-y"
        site_config      = { application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" } }
      }
    }
  }

  expect_failures = [var.web_apps]
}

run "rejects_identity_with_create_uai" {
  command = plan

  variables {
    web_apps = {
      "app-bad-ldo-uks-tst-01" = {
        identity    = { type = "SystemAssigned" }
        site_config = { application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" } }
      }
    }
  }

  expect_failures = [var.web_apps]
}

run "rejects_cors_wildcard_with_credentials" {
  command = plan

  variables {
    web_apps = {
      "app-bad-ldo-uks-tst-01" = {
        site_config = {
          application_stack = { current_stack = "dotnet", dotnet_version = "v8.0" }
          cors = {
            allowed_origins     = ["*"]
            support_credentials = true
          }
        }
      }
    }
  }

  expect_failures = [var.web_apps]
}
