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
  value       = try(var.settings.audit.s3_key_prefix, "session-manager/")
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
  description = "Resolved list of IAM role ARNs granted access to the audit bucket and KMS key, merging settings.allowed_iam_role_arns with roles looked up from settings.allowed_iam_role_names."
  value       = local.allowed_iam_role_arns
}

output "delegated_administrator_account_id" {
  description = "Account ID registered as SSM delegated administrator. Empty when delegation mode is disabled."
  value       = try(aws_organizations_delegated_administrator.this[0].account_id, "")
}
