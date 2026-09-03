##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

output "audit_bucket_id" {
  description = "Name of the S3 bucket holding Session Manager audit logs. Empty in delegation mode."
  value       = try(module.ssm_bucket.s3_bucket_id, "")

  precondition {
    condition     = local.is_delegated || local.ssm_logs_bucket_length <= 63
    error_message = "The generated audit bucket name is ${local.ssm_logs_bucket_length} characters, exceeding the S3 limit of 63. Shorten the organization unit or environment names, or set settings.bucket.name explicitly."
  }
}

output "audit_bucket_arn" {
  description = "ARN of the S3 bucket holding Session Manager audit logs. Empty in delegation mode."
  value       = try(module.ssm_bucket.s3_bucket_arn, "")
}

output "audit_bucket_key_prefix" {
  description = "Key prefix under which Session Manager writes audit logs in the bucket."
  value       = local.audit_s3_key_prefix
}

output "kms_key_id" {
  description = "Key ID of the KMS key used to encrypt session data, whether created by this module or supplied. Empty when no customer managed key is in use."
  value       = local.kms_key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt session data. Empty when no customer managed key is in use."
  value       = local.kms_key_arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key created by this module. Empty when the module does not create a key."
  value       = try(aws_kms_alias.this[0].name, "")
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group receiving session logs. Empty when CloudWatch logging is disabled."
  value       = try(aws_cloudwatch_log_group.this[0].name, "")
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group receiving session logs. Empty when CloudWatch logging is disabled."
  value       = try(aws_cloudwatch_log_group.this[0].arn, "")
}

output "session_document_name" {
  description = "Name of the SSM Session document holding the regional Session Manager preferences. Empty in delegation mode."
  value       = try(aws_ssm_document.session_manager[0].name, "")
}

output "session_document_arn" {
  description = "ARN of the SSM Session document holding the regional Session Manager preferences. Empty in delegation mode."
  value       = try(aws_ssm_document.session_manager[0].arn, "")
}

output "allowed_iam_role_arns" {
  description = "Resolved list of IAM role ARNs granted access to the audit bucket and KMS key, merging settings.allowed_iam_role_arns with the exact names and wildcard patterns resolved from settings.allowed_iam_role_names."
  value       = local.allowed_iam_role_arns
}

output "admin_iam_role_arns" {
  description = "Resolved list of IAM role ARNs granted full object access on the audit bucket (read, create, delete, multipart and listing), merging settings.admin_iam_role_arns with the exact names and wildcard patterns resolved from settings.admin_iam_role_names."
  value       = local.admin_iam_role_arns
}

output "default_host_management_role_name" {
  description = "Name of the IAM role Systems Manager assumes for Default Host Management Configuration. Empty when the module does not create the role."
  value       = try(aws_iam_role.default_host_management[0].name, "")
}

output "default_host_management_role_arn" {
  description = "ARN of the IAM role Systems Manager assumes for Default Host Management Configuration. Empty when the module does not create the role."
  value       = try(aws_iam_role.default_host_management[0].arn, "")
}

output "default_host_management_setting_value" {
  description = "Value written to the Default Host Management Configuration service setting, as the role path and name Systems Manager expects. Empty when Default Host Management Configuration is disabled."
  value       = local.dhmc_enabled ? local.dhmc_setting_value : ""
}

output "inventory_association_id" {
  description = "ID of the State Manager association running AWS-GatherSoftwareInventory. Empty when Inventory collection is disabled."
  value       = try(aws_ssm_association.inventory[0].association_id, "")
}

output "inventory_association_name" {
  description = "Name of the State Manager association running AWS-GatherSoftwareInventory. Empty when Inventory collection is disabled."
  value       = try(aws_ssm_association.inventory[0].association_name, "")
}

output "resource_data_sync_name" {
  description = "Name of the Inventory resource data sync. Empty when resource data sync is disabled."
  value       = try(aws_ssm_resource_data_sync.inventory[0].name, "")
}

output "resource_data_sync_bucket" {
  description = "Name of the S3 bucket receiving synchronised Inventory data. Empty when resource data sync is disabled."
  value       = local.resource_data_sync_enabled ? local.resource_data_sync_bucket : ""
}

output "resource_data_sync_prefix" {
  description = "Key prefix under which resource data sync writes Inventory data. Empty when resource data sync is disabled or writes to the bucket root."
  value       = local.resource_data_sync_enabled ? local.resource_data_sync_prefix : ""
}

output "remote_desktop_recording_bucket" {
  description = "Name of the S3 bucket receiving Fleet Manager Remote Desktop connection recordings. Empty when RDP recording is disabled."
  value       = local.rdp_recording_enabled ? local.rdp_recording_bucket : ""
}

output "remote_desktop_recording_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Remote Desktop recordings while Systems Manager processes them. Empty when RDP recording is disabled."
  value       = local.rdp_recording_enabled ? local.rdp_recording_kms_key_arn : ""
}

output "delegated_administrator_account_id" {
  description = "Account ID registered as SSM delegated administrator. Empty when delegation mode is disabled."
  value       = try(aws_organizations_delegated_administrator.this[0].account_id, "")
}

output "dhmc_quicksetup_manager_arn" {
  description = "ARN of the Quick Setup configuration manager deploying Default Host Management Configuration. Empty when settings.dhmc is disabled."
  value       = try(aws_ssmquicksetup_configuration_manager.dhmc[0].manager_arn, "")
}

output "host_management_quicksetup_manager_arn" {
  description = "ARN of the Quick Setup configuration manager deploying Host Management. Empty when settings.host_management is disabled."
  value       = try(aws_ssmquicksetup_configuration_manager.host[0].manager_arn, "")
}

output "patch_quicksetup_manager_arn" {
  description = "ARN of the Quick Setup configuration manager deploying the Patch Policy. Empty when settings.patch is disabled."
  value       = try(aws_ssmquicksetup_configuration_manager.patch[0].manager_arn, "")
}

output "patch_policy_name" {
  description = "Name of the patch policy, which Quick Setup also applies to targeted instances as a tag. Empty when settings.patch is disabled."
  value       = local.patch_quicksetup_enabled ? try(var.settings.patch.policy_name, local.system_name_short) : ""
}
