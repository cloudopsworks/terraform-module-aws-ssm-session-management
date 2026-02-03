##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

# settings:
#   random_bucket_suffix: true                      # (Optional) Whether to add a random suffix to the S3 bucket name. Default: true
#   allowed_iam_role_arns: []                       # (Optional) List of IAM role ARNs allowed to access the S3 bucket and KMS key. Default: []
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
#     run_as: ""                                    # (Optional) The user to run as during the session. Default: ""
#     timeout: 20                                   # (Optional) Idle session timeout in minutes. Default: 20
#     max_duration: 60                              # (Optional) Maximum session duration in minutes. Default: 60
#   audit:                                          # (Optional) Audit logs settings for S3
#     transition_days: 30                           # (Optional) Number of days before transitioning logs to STANDARD_IA. Default: 30
#     archive_days: 60                              # (Optional) Number of days before transitioning logs to GLACIER. Default: 60
#     retention_years: 5                            # (Optional) Number of years to retain logs. Default: 5
#   cloudwatch:                                     # (Optional) CloudWatch logging settings
#     enabled: false                                # (Optional) Whether to enable CloudWatch logging. Default: false
#     retention: 7                                  # (Optional) CloudWatch log retention in days. Default: 7
variable "settings" {
  description = "Settings for SSM Session Manager & SSM Fleet Manager"
  type        = any
  default     = {}
}