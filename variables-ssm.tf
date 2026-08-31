##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

# settings:
#   random_bucket_suffix: true                      # (Optional) Deprecated, use bucket.random_suffix instead. Default: true
#   allowed_iam_role_arns: []                       # (Optional) List of IAM role ARNs allowed to access the S3 bucket and KMS key. Default: []
#   allowed_iam_role_names: []                      # (Optional) List of IAM role names in the current account, resolved to ARNs and merged with allowed_iam_role_arns. Default: []
#   organization:                                   # (Optional) Organization delegation settings. When delegated is true ONLY the delegated administrator registrations are created.
#     delegated: false                              # (Optional) Whether to run in delegation mode, registering SSM delegated administrators instead of session logging resources. Default: false
#     account_id: ""                                # (Required when delegated is true) Account ID to register as SSM delegated administrator.
#   bucket:                                         # (Optional) Audit log S3 bucket settings
#     name: ""                                      # (Optional) Explicit bucket name. When set, no name is generated and no random suffix is added. Default: "" (generate "ssm-session-auditlogs-<system-name>")
#     random_suffix: true                           # (Optional) Whether to append a random 8 character suffix to the generated bucket name. Ignored when name is set. Default: true
#     versioning: false                             # (Optional) Whether to enable versioning on the audit bucket. Default: false
#   kms:                                            # (Optional) KMS configuration for encryption
#     enabled: true                                 # (Optional) Whether to create a new KMS key. Default: true
#     key_alias: ""                                 # (Optional) Existing KMS key alias to use if kms.enabled is false. Default: ""
#     key_id: ""                                    # (Optional) Existing KMS key ID to use if kms.enabled is false. Default: ""
#     deletion_window: 30                           # (Optional) Deletion window in days for the KMS key. Default: 30
#     enable_key_rotation: true                     # (Optional) Whether to enable key rotation for the KMS key. Default: true
#     rotation_period_in_days: 90                   # (Optional) Rotation period in days for the KMS key. Default: 90
#     multi_region: false                           # (Optional) Whether the KMS key is multi-region. Default: false
#     alias_name: "ssm-session-mgmt-key"            # (Optional) Alias name for the KMS key. Default: "ssm-session-mgmt-key-${local.system_name}"
#   session:                                        # (Optional) Session Manager settings
#     run_as: ""                                    # (Optional) The OS user to run the session as. Default: ""
#     run_as_enabled: false                         # (Optional) Whether Session Manager honours run_as. Default: true when run_as is non-empty, false otherwise
#     timeout: 20                                   # (Optional) Idle session timeout in minutes, valid values 1-60. Default: 20
#     max_duration: 60                              # (Optional) Maximum session duration in minutes, valid values 1-1440. Default: 60
#     shell_profile:                                # (Optional) Commands run at session start, per platform
#       linux: ""                                   # (Optional) Shell commands to run when a Linux session starts. Default: ""
#       windows: ""                                 # (Optional) Shell commands to run when a Windows session starts. Default: ""
#   audit:                                          # (Optional) Audit logs settings for S3
#     s3_key_prefix: "session-manager/"             # (Optional) Key prefix for session logs written to the bucket. Default: "session-manager/"
#     transition_days: 30                           # (Optional) Number of days before transitioning logs to STANDARD_IA. Default: 30
#     archive_days: 60                              # (Optional) Number of days before transitioning logs to GLACIER. Default: 60
#     retention_years: 5                            # (Optional) Number of years to retain logs. Default: 5
#     abort_multipart_days: 7                       # (Optional) Days before aborting incomplete multipart uploads. Default: 7
#   cloudwatch:                                     # (Optional) CloudWatch logging settings
#     enabled: false                                # (Optional) Whether to enable CloudWatch logging. Default: false
#     retention: 7                                  # (Optional) CloudWatch log retention in days. Default: 7
#     streaming: false                              # (Optional) Whether to stream session output continuously instead of on session end. Default: false
variable "settings" {
  description = "Settings for SSM Session Manager & SSM Fleet Manager"
  type        = any
  default     = {}

  validation {
    condition     = try(tonumber(try(var.settings.session.timeout, 20)) >= 1 && tonumber(try(var.settings.session.timeout, 20)) <= 60, false)
    error_message = "settings.session.timeout must be a number of minutes between 1 and 60."
  }

  validation {
    condition     = try(tonumber(try(var.settings.session.max_duration, 60)) >= 1 && tonumber(try(var.settings.session.max_duration, 60)) <= 1440, false)
    error_message = "settings.session.max_duration must be a number of minutes between 1 and 1440."
  }

  validation {
    condition     = try(tonumber(try(var.settings.audit.retention_years, 5)) >= 1, false)
    error_message = "settings.audit.retention_years must be a number of years greater than or equal to 1."
  }

  validation {
    condition     = !try(var.settings.organization.delegated, false) || try(var.settings.organization.account_id, "") != ""
    error_message = "settings.organization.account_id is required when settings.organization.delegated is true."
  }

  validation {
    condition     = try(var.settings.bucket.name, "") == "" || try(length(var.settings.bucket.name) >= 3 && length(var.settings.bucket.name) <= 63, false)
    error_message = "settings.bucket.name must be between 3 and 63 characters when set."
  }
}
