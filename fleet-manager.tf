##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  # Every Fleet Manager setting below is account and Region wide, so the whole block is
  # opt-in. Like the rest of the logging stack it is skipped in delegation mode, where the
  # module only registers delegated administrators.
  fleet_manager_enabled = try(var.settings.fleet_manager.enabled, false) && !local.is_delegated
}

##
# Default Host Management Configuration
#
# Lets Systems Manager manage every EC2 instance in this account and Region as a managed
# node without an instance profile. Instances still need IMDSv2 and SSM Agent 3.2.582.0 or
# later; an instance profile that already allows ssm:UpdateInstanceInformation takes
# precedence over these credentials and keeps the instance off DHMC.
##
locals {
  dhmc_enabled = local.fleet_manager_enabled && try(var.settings.fleet_manager.default_host_management.enabled, false)

  # The console-created role is AWSSystemsManagerDefaultEC2InstanceManagementRole under the
  # /service-role/ path. Keeping that name and path means an account already configured
  # from the console can be imported into this module without recreating anything.
  dhmc_role_name = try(var.settings.fleet_manager.default_host_management.role_name, "AWSSystemsManagerDefaultEC2InstanceManagementRole")
  dhmc_role_path = try(var.settings.fleet_manager.default_host_management.role_path, "/service-role/")

  dhmc_create_role = local.dhmc_enabled && try(var.settings.fleet_manager.default_host_management.create_role, true)

  # UpdateServiceSetting takes the role path and name rather than an ARN, and without the
  # leading slash: "service-role/AWSSystemsManagerDefaultEC2InstanceManagementRole".
  dhmc_setting_value = trimprefix("${local.dhmc_role_path}${local.dhmc_role_name}", "/")

  # Anything beyond the AWS managed default policy attached below — CloudWatch agent, patch
  # association — is the caller's to add, and applies to every managed instance in the
  # Region. Kept free of any data source so the for_each keys are known at plan time.
  dhmc_additional_policy_arns = local.dhmc_create_role ? distinct(try(var.settings.fleet_manager.default_host_management.additional_policy_arns, [])) : []

  # The AWS managed policy grants no access to a customer owned audit bucket or CMK, so
  # without this nodes managed through DHMC would connect but fail to write their session
  # logs to the bucket, log group and key this module creates.
  dhmc_session_logging = local.dhmc_create_role && try(var.settings.fleet_manager.default_host_management.session_logging_access, true)
}

resource "aws_iam_role" "default_host_management" {
  count       = local.dhmc_create_role ? 1 : 0
  name        = local.dhmc_role_name
  path        = local.dhmc_role_path
  description = "Default Host Management Configuration role assumed by Systems Manager to manage EC2 instances as managed nodes"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = local.all_tags
}

# AmazonSSMManagedEC2InstanceDefaultPolicy is the minimum set Systems Manager needs to
# manage an instance, and is always attached.
resource "aws_iam_role_policy_attachment" "default_host_management" {
  count      = local.dhmc_create_role ? 1 : 0
  role       = aws_iam_role.default_host_management[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
}

resource "aws_iam_role_policy_attachment" "default_host_management_additional" {
  for_each   = toset(local.dhmc_additional_policy_arns)
  role       = aws_iam_role.default_host_management[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "default_host_management_session_logging" {
  count = local.dhmc_session_logging ? 1 : 0
  name  = "session-logging"
  role  = aws_iam_role.default_host_management[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "WriteSessionLogsToAuditBucket"
          Effect   = "Allow"
          Action   = "s3:PutObject"
          Resource = "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}/*"
        },
        {
          # Session Manager reads the bucket encryption configuration before writing, to
          # decide which key to encrypt the log with.
          Sid      = "ReadAuditBucketEncryptionConfiguration"
          Effect   = "Allow"
          Action   = "s3:GetEncryptionConfiguration"
          Resource = "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}"
        }
      ],
      local.has_kms_key ? [{
        Sid    = "UseSessionEncryptionKey"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = local.kms_key_arn
      }] : [],
      local.cloudwatch_enabled ? [{
        Sid    = "WriteSessionLogsToCloudWatch"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.this[0].arn}:*"
      }] : [],
      local.cloudwatch_enabled ? [{
        # DescribeLogGroups is a list operation and admits no resource scope. Gated on its
        # own because its shape differs from the statement above, and a single conditional
        # returning both has no consistent type with the empty alternative.
        Sid      = "DiscoverSessionLogGroup"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      }] : []
    )
  })
}

resource "aws_ssm_service_setting" "default_host_management" {
  count         = local.dhmc_enabled ? 1 : 0
  setting_id    = "/ssm/managed-instance/default-ec2-instance-management-role"
  setting_value = local.dhmc_setting_value

  # Systems Manager starts handing the role's credentials to instances as soon as the
  # setting flips, so the permissions must already be attached at that point.
  depends_on = [
    aws_iam_role_policy_attachment.default_host_management,
    aws_iam_role_policy_attachment.default_host_management_additional,
    aws_iam_role_policy.default_host_management_session_logging,
  ]
}

##
# Inventory collection
#
# Fleet Manager's node detail views — applications, network configuration, Windows updates —
# are rendered from Inventory, which is only populated by an association running
# AWS-GatherSoftwareInventory. Systems Manager permits exactly one inventory association per
# node, so enabling this in an account that already has one will fail on the overlap.
##
locals {
  inventory_enabled = local.fleet_manager_enabled && try(var.settings.fleet_manager.inventory.enabled, false)

  inventory_targets = try(var.settings.fleet_manager.inventory.targets, [{
    key    = "InstanceIds"
    values = ["*"]
  }])

  # AWS-GatherSoftwareInventory takes "Enabled" or "Disabled" per category, and every one of
  # these defaults to "Enabled" in the document itself.
  inventory_categories = {
    applications                = try(var.settings.fleet_manager.inventory.applications, "Enabled")
    awsComponents               = try(var.settings.fleet_manager.inventory.aws_components, "Enabled")
    customInventory             = try(var.settings.fleet_manager.inventory.custom_inventory, "Enabled")
    instanceDetailedInformation = try(var.settings.fleet_manager.inventory.instance_detailed_information, "Enabled")
    networkConfig               = try(var.settings.fleet_manager.inventory.network_config, "Enabled")
    services                    = try(var.settings.fleet_manager.inventory.services, "Enabled")
    windowsRoles                = try(var.settings.fleet_manager.inventory.windows_roles, "Enabled")
    windowsUpdates              = try(var.settings.fleet_manager.inventory.windows_updates, "Enabled")
  }

  # files and windowsRegistry take a JSON document rather than Enabled/Disabled and carry no
  # document default, so they are only sent once the caller actually configures them.
  inventory_documents = {
    for key, value in {
      files           = try(var.settings.fleet_manager.inventory.files, "")
      windowsRegistry = try(var.settings.fleet_manager.inventory.windows_registry, "")
    } : key => value if value != ""
  }

  inventory_parameters = merge(local.inventory_categories, local.inventory_documents)
}

resource "aws_ssm_association" "inventory" {
  count               = local.inventory_enabled ? 1 : 0
  name                = "AWS-GatherSoftwareInventory"
  association_name    = try(var.settings.fleet_manager.inventory.association_name, "ssm-inventory-${local.system_name}")
  schedule_expression = try(var.settings.fleet_manager.inventory.schedule, "rate(1 day)")

  # Inventory is a metadata scan, so letting it run once on apply costs nothing and gets
  # Fleet Manager populated without waiting out the first interval.
  apply_only_at_cron_interval = try(var.settings.fleet_manager.inventory.apply_only_at_cron_interval, false)

  max_concurrency = try(var.settings.fleet_manager.inventory.max_concurrency, null)
  max_errors      = try(var.settings.fleet_manager.inventory.max_errors, null)

  parameters = local.inventory_parameters

  dynamic "targets" {
    for_each = local.inventory_targets
    content {
      key    = targets.value.key
      values = targets.value.values
    }
  }
}

##
# Resource data sync
#
# Aggregates the Inventory data collected above into a single S3 bucket so it can be queried
# with Athena. Managed from Fleet Manager, Account management, Resource data sync.
##
locals {
  resource_data_sync_enabled = local.fleet_manager_enabled && try(var.settings.fleet_manager.resource_data_sync.enabled, false)

  # Derived from configuration rather than from the resolved bucket name, which carries the
  # random suffix and is therefore unknown at plan time. The S3 bucket policy switches on
  # this, and a count/for_each may not depend on an unknown value.
  resource_data_sync_uses_audit_bucket = local.resource_data_sync_enabled && try(var.settings.fleet_manager.resource_data_sync.bucket_name, "") == ""

  resource_data_sync_bucket = local.resource_data_sync_uses_audit_bucket ? local.ssm_logs_bucket : try(var.settings.fleet_manager.resource_data_sync.bucket_name, "")

  # Normalised without a trailing slash so the bucket policy resource patterns below compose
  # cleanly whether or not the caller wrote one.
  resource_data_sync_prefix = trimsuffix(try(var.settings.fleet_manager.resource_data_sync.prefix, "inventory"), "/")

  # Same plan-time reasoning as above: the KMS key policy switches on this, so it is derived
  # from has_kms_key — which is configuration — and never from the resolved key ARN.
  resource_data_sync_uses_module_key = local.resource_data_sync_uses_audit_bucket && local.has_kms_key && try(var.settings.fleet_manager.resource_data_sync.kms_key_arn, "") == ""

  resource_data_sync_kms_key_arn = try(var.settings.fleet_manager.resource_data_sync.kms_key_arn, "") != "" ? var.settings.fleet_manager.resource_data_sync.kms_key_arn : (
    local.resource_data_sync_uses_module_key ? local.kms_key_arn : ""
  )

  # Systems Manager writes each account's data under its own accountid= partition, and the
  # bucket policy has to grant exactly that shape.
  resource_data_sync_object_pattern = format(
    "arn:%s:s3:::%s/%saccountid=%s/*",
    data.aws_partition.current.partition,
    local.ssm_logs_bucket,
    local.resource_data_sync_prefix != "" ? "${local.resource_data_sync_prefix}/*/" : "*/",
    data.aws_caller_identity.current.account_id
  )
}

resource "aws_ssm_resource_data_sync" "inventory" {
  count = local.resource_data_sync_enabled ? 1 : 0
  name  = try(var.settings.fleet_manager.resource_data_sync.name, "ssm-inventory-${local.system_name}")

  s3_destination {
    bucket_name = local.resource_data_sync_bucket
    region      = try(var.settings.fleet_manager.resource_data_sync.region, data.aws_region.current.region)
    prefix      = local.resource_data_sync_prefix != "" ? local.resource_data_sync_prefix : null
    kms_key_arn = local.resource_data_sync_kms_key_arn != "" ? local.resource_data_sync_kms_key_arn : null
    sync_format = "JsonSerDe"
  }

  # The sync validates the destination bucket policy on creation, so the bucket and its
  # policy must exist first.
  depends_on = [module.ssm_bucket]
}

##
# Remote Desktop connection recording
#
# Fleet Manager Remote Desktop otherwise needs no configuration of its own: an RDP
# connection applies the same Session Manager preferences written to the
# SSM-SessionManagerRunShell document. Recording is the one thing that is separately
# configurable, and it is exposed only through Cloud Control, hence the awscc provider.
#
# The console reaches these settings under Settings, Just-in-time node access, RDP
# recording. Recordings are written by the ssm-guiconnect service principal, which is why
# the audit bucket policy and the KMS key policy both need statements of their own.
##
locals {
  rdp_recording_enabled = local.fleet_manager_enabled && try(var.settings.fleet_manager.remote_desktop.recording.enabled, false)

  # Same plan-time reasoning as the resource data sync: the bucket and key policies switch
  # on this, so it is derived from configuration and never from the resolved bucket name.
  rdp_recording_uses_audit_bucket = local.rdp_recording_enabled && try(var.settings.fleet_manager.remote_desktop.recording.bucket_name, "") == ""

  rdp_recording_bucket = local.rdp_recording_uses_audit_bucket ? local.ssm_logs_bucket : try(var.settings.fleet_manager.remote_desktop.recording.bucket_name, "")

  rdp_recording_bucket_owner = try(var.settings.fleet_manager.remote_desktop.recording.bucket_owner, "") != "" ? var.settings.fleet_manager.remote_desktop.recording.bucket_owner : data.aws_caller_identity.current.account_id

  # GUI Connect uses this key to encrypt the recording while it is still being processed on
  # Systems Manager resources, before it lands in S3. It must be a symmetric customer
  # managed key with encrypt/decrypt usage, in the same Region as the node.
  rdp_recording_uses_module_key = local.rdp_recording_enabled && local.has_kms_key && try(var.settings.fleet_manager.remote_desktop.recording.kms_key_arn, "") == ""

  rdp_recording_kms_key_arn = try(var.settings.fleet_manager.remote_desktop.recording.kms_key_arn, "") != "" ? var.settings.fleet_manager.remote_desktop.recording.kms_key_arn : (
    local.rdp_recording_uses_module_key ? local.kms_key_arn : ""
  )

  # The bucket's own SSE-KMS key needs a separate grant, scoped through S3, so that
  # ssm-guiconnect can write an encrypted object into it. That is only this module's to add
  # when the recording lands in the audit bucket and that bucket is encrypted with our key.
  rdp_recording_needs_bucket_key_grant = local.rdp_recording_uses_audit_bucket && local.has_kms_key
}

resource "awscc_ssmguiconnect_preferences" "remote_desktop" {
  count = local.rdp_recording_enabled ? 1 : 0

  connection_recording_preferences = {
    kms_key_arn = local.rdp_recording_kms_key_arn
    recording_destinations = {
      # The schema accepts exactly one bucket, minimum and maximum alike.
      s3_buckets = [{
        bucket_name  = local.rdp_recording_bucket
        bucket_owner = local.rdp_recording_bucket_owner
      }]
    }
  }

  # Recording fails asynchronously with a ProcessingError rather than a clear error at
  # connection time when the destination policies are not in place yet.
  depends_on = [module.ssm_bucket]

  lifecycle {
    precondition {
      condition     = local.rdp_recording_kms_key_arn != ""
      error_message = "settings.fleet_manager.remote_desktop.recording requires a customer managed KMS key. Either leave settings.kms.enabled at its default so this module creates one, supply settings.kms.key_id or settings.kms.key_alias, or set settings.fleet_manager.remote_desktop.recording.kms_key_arn explicitly."
    }
  }
}
