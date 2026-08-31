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
#   allowed_iam_role_names: []                      # (Optional) List of IAM role names in the current account, resolved to ARNs and merged with allowed_iam_role_arns. Entries may use "*" and "?" wildcards (e.g. "ssm-*"), which are resolved by listing roles at plan time. Default: []
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
#   fleet_manager:                                  # (Optional) Fleet Manager settings. Every setting below is account and Region wide and is ignored in delegation mode.
#     enabled: false                                # (Optional) Master toggle for the whole fleet_manager block. Nothing below is created unless this is true. Default: false
#     default_host_management:                      # (Optional) Default Host Management Configuration, which lets Systems Manager manage every EC2 instance in the account and Region without an instance profile.
#       enabled: false                              # (Optional) Whether to turn on Default Host Management Configuration. Requires IMDSv2 and SSM Agent 3.2.582.0 or later on the instances. Default: false
#       create_role: true                           # (Optional) Whether to create the IAM role. Set false to point the setting at a role managed elsewhere. Default: true
#       role_name: ""                               # (Optional) Name of the IAM role Systems Manager assumes. Default: "AWSSystemsManagerDefaultEC2InstanceManagementRole"
#       role_path: "/service-role/"                 # (Optional) IAM path of that role, leading and trailing slash included. Default: "/service-role/"
#       additional_policy_arns: []                  # (Optional) Extra managed policy ARNs to attach to the created role, e.g. CloudWatchAgentServerPolicy. Applies to every managed instance in the Region. Default: []
#       session_logging_access: true                # (Optional) Whether to attach an inline policy letting managed nodes write session logs to this module's audit bucket, KMS key and log group. Ignored when create_role is false. Default: true
#     inventory:                                    # (Optional) Inventory collection, which populates the Fleet Manager node detail views. Systems Manager permits only one inventory association per node.
#       enabled: false                              # (Optional) Whether to create the AWS-GatherSoftwareInventory association. Default: false
#       schedule: "rate(1 day)"                     # (Optional) Rate or cron expression for the collection schedule, minimum 30 minutes. Default: "rate(1 day)"
#       association_name: ""                        # (Optional) Name of the State Manager association, 3-128 characters of [A-Za-z0-9_.-]. Default: "ssm-inventory-${local.system_name}"
#       apply_only_at_cron_interval: false          # (Optional) Skip the immediate run on apply and wait for the first scheduled interval. Default: false
#       max_concurrency: ""                         # (Optional) Nodes to run against at once, as a number or a percentage such as "10%". Default: "" (unset, AWS decides)
#       max_errors: ""                              # (Optional) Errors tolerated before the association stops, as a number or a percentage. Default: "" (unset, AWS decides)
#       targets: []                                 # (Optional) List of {key, values} target blocks, max 5. Default: [{ key: "InstanceIds", values: ["*"] }] (every managed node)
#       applications: "Enabled"                     # (Optional) Collect installed application metadata. Values: Enabled, Disabled. Default: "Enabled"
#       aws_components: "Enabled"                   # (Optional) Collect AWS component metadata such as amazon-ssm-agent. Values: Enabled, Disabled. Default: "Enabled"
#       custom_inventory: "Enabled"                 # (Optional) Collect custom inventory metadata. Values: Enabled, Disabled. Default: "Enabled"
#       instance_detailed_information: "Enabled"    # (Optional) Collect CPU model, speed and core count. Values: Enabled, Disabled. Default: "Enabled"
#       network_config: "Enabled"                   # (Optional) Collect network configuration metadata. Values: Enabled, Disabled. Default: "Enabled"
#       services: "Enabled"                         # (Optional) Collect Windows service configuration. Windows only. Values: Enabled, Disabled. Default: "Enabled"
#       windows_roles: "Enabled"                    # (Optional) Collect Windows roles. Windows only. Values: Enabled, Disabled. Default: "Enabled"
#       windows_updates: "Enabled"                  # (Optional) Collect installed Windows updates. Windows only. Values: Enabled, Disabled. Default: "Enabled"
#       files: ""                                   # (Optional) JSON string selecting files to inventory, e.g. '[{"Path":"/usr/bin","Pattern":["*ssm*"],"Recursive":false}]'. Only sent when non-empty. Default: ""
#       windows_registry: ""                        # (Optional) JSON string selecting Windows registry keys to inventory. Only sent when non-empty. Default: ""
#     remote_desktop:                               # (Optional) Fleet Manager Remote Desktop. Connections otherwise inherit the Session Manager preferences above; recording is the only separately configurable setting.
#       recording:                                  # (Optional) RDP connection recording, written to S3 by the ssm-guiconnect service principal. Console equivalent: Settings, Just-in-time node access, RDP recording.
#         enabled: false                            # (Optional) Whether to record RDP connections. Requires a customer managed KMS key. Default: false
#         bucket_name: ""                           # (Optional) Destination bucket. When empty this module's audit bucket is used and the required bucket policy and KMS grants are added automatically; when set, that bucket's policy is the caller's responsibility. Default: ""
#         bucket_owner: ""                          # (Optional) Account ID owning the destination bucket. Default: "" (the current account)
#         kms_key_arn: ""                           # (Optional) Symmetric encrypt/decrypt customer managed key used to encrypt the recording while Systems Manager processes it, in the same region as the node. Default: "" (this module's key)
#     resource_data_sync:                           # (Optional) Aggregates the collected Inventory into an S3 bucket for querying with Athena.
#       enabled: false                              # (Optional) Whether to create the resource data sync. Default: false
#       name: ""                                    # (Optional) Name of the sync. Default: "ssm-inventory-${local.system_name}"
#       bucket_name: ""                             # (Optional) Destination bucket. When empty the module's own audit bucket is used and the required bucket policy and KMS grants are added automatically; when set, that bucket's policy is the caller's responsibility. Default: ""
#       prefix: "inventory"                         # (Optional) Key prefix for the synchronised data. Set to "" to write at the bucket root. Default: "inventory"
#       region: ""                                  # (Optional) Region of the destination bucket. Default: "" (the current region)
#       kms_key_arn: ""                             # (Optional) KMS key ARN used to encrypt the synchronised data. Default: "" (this module's key when the audit bucket is the destination, otherwise unencrypted by the sync)
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

  validation {
    condition = alltrue([
      for name in try(var.settings.allowed_iam_role_names, []) : can(regex("[^*?]", name))
    ])
    error_message = "Each settings.allowed_iam_role_names entry must contain at least one literal character. A pattern of only wildcards would match every IAM role in the account."
  }

  validation {
    condition     = can(regex("^/([^/]+/)*$", try(var.settings.fleet_manager.default_host_management.role_path, "/service-role/")))
    error_message = "settings.fleet_manager.default_host_management.role_path must begin and end with a slash, for example \"/service-role/\" or \"/\"."
  }

  # Systems Manager caps an association at 5 target blocks.
  validation {
    condition     = length(try(var.settings.fleet_manager.inventory.targets, [])) <= 5
    error_message = "settings.fleet_manager.inventory.targets accepts at most 5 target blocks."
  }

  # AWS-GatherSoftwareInventory rejects anything but these two, and a typo would otherwise
  # only surface once the association had already been created.
  validation {
    condition = alltrue([
      for key in [
        "applications", "aws_components", "custom_inventory", "instance_detailed_information",
        "network_config", "services", "windows_roles", "windows_updates",
      ] : contains(["Enabled", "Disabled"], try(var.settings.fleet_manager.inventory[key], "Enabled"))
    ])
    error_message = "Every settings.fleet_manager.inventory collection category must be either \"Enabled\" or \"Disabled\"."
  }

  # Mirrors the has_kms_key local: GUI Connect will not record without a customer managed
  # key, and catching it here beats a failure at connection time.
  validation {
    condition = !try(var.settings.fleet_manager.remote_desktop.recording.enabled, false) || (
      try(var.settings.fleet_manager.remote_desktop.recording.kms_key_arn, "") != "" ||
      try(var.settings.kms.enabled, true) ||
      try(var.settings.kms.key_id, "") != "" ||
      try(var.settings.kms.key_alias, "") != ""
    )
    error_message = "settings.fleet_manager.remote_desktop.recording requires a customer managed KMS key. Leave settings.kms.enabled at its default, supply settings.kms.key_id or settings.kms.key_alias, or set settings.fleet_manager.remote_desktop.recording.kms_key_arn."
  }
}
