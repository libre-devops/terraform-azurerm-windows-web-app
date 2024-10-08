output "service_plans_ids" {
  description = "The IDs of the Service Plans."
  value       = { for plan in azurerm_service_plan.service_plan : plan.name => plan.id }
}

output "web_app_identities" {
  description = "The identities of the Web app."
  value = {
    for key, value in azurerm_windows_web_app.web_app : key =>
    length(value.identity) > 0 ? {
      type         = try(value.identity[0].type, null)
      principal_id = try(value.identity[0].principal_id, null)
      tenant_id    = try(value.identity[0].tenant_id, null)
      } : {
      type         = null
      principal_id = null
      tenant_id    = null
    }
  }
}

output "web_app_identity_principal_ids" {
  description = "The Principal IDs associated with the Managed Service Identity."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.identity[0].principal_id }
}

output "web_app_identity_tenant_ids" {
  description = "The Tenant IDs associated with the Managed Service Identity."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.identity[0].tenant_id }
}

output "web_app_names" {
  description = "The default name of the windows Function Apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.name }
}

output "web_apps_custom_domain_verification_id" {
  description = "The custom domain verification IDs of the windows Function Apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.custom_domain_verification_id }
}

output "web_apps_default_hostnames" {
  description = "The default hostnames of the windows Function Apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.default_hostname }
}

output "web_apps_outbound_ip_addresses" {
  description = "The outbound IP addresses of the windows Function Apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.outbound_ip_addresses }
}

output "web_apps_possible_outbound_ip_addresses" {
  description = "The possible outbound IP addresses of the windows Function Apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.possible_outbound_ip_addresses }
}

output "web_apps_site_credentials" {
  description = "The site credentials for the windows Function Apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.site_credential }
}

output "windows_web_apps_custom_domain_verification_id" {
  description = "The custom domain verification IDs of the windows web apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.custom_domain_verification_id }
}

output "windows_web_apps_hosting_environment_id" {
  description = "The hosting environment IDs of the windows web apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.hosting_environment_id }
}

output "windows_web_apps_ids" {
  description = "The IDs of the windows Function Apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.id }
}

output "windows_web_apps_kind" {
  description = "The kind value of the windows web apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.kind }
}

output "windows_web_apps_outbound_ip_address_list" {
  description = "The list of outbound IP addresses of the windows web apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.outbound_ip_address_list }
}

output "windows_web_apps_possible_outbound_ip_address_list" {
  description = "The list of possible outbound IP addresses of the windows web apps."
  value       = { for app in azurerm_windows_web_app.web_app : app.name => app.possible_outbound_ip_address_list }
}
