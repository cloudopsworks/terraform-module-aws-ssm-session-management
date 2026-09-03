##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  kms_create = try(var.settings.kms.enabled, true) && !local.is_delegated

  # Key resolution order: the key created by this module first, then an explicitly
  # supplied key id, then a supplied alias. Empty when the module manages no CMK at
  # all, which callers must treat as "use the AWS managed key / no CMK".
  kms_key_id = try(
    aws_kms_key.this[0].key_id,
    data.aws_kms_key.existing[0].key_id,
    data.aws_kms_alias.existing[0].target_key_id,
    ""
  )

  kms_key_arn = try(
    aws_kms_key.this[0].arn,
    data.aws_kms_key.existing[0].arn,
    data.aws_kms_alias.existing[0].target_key_arn,
    ""
  )

  # Derived from configuration rather than from the resolved ARN so it stays known at
  # plan time, keeping dependent arguments out of "known after apply".
  has_kms_key = local.kms_create || try(var.settings.kms.key_id, "") != "" || try(var.settings.kms.key_alias, "") != ""
}

data "aws_kms_alias" "existing" {
  count = !try(var.settings.kms.enabled, true) && try(var.settings.kms.key_alias, "") != "" ? 1 : 0
  name  = var.settings.kms.key_alias
}

data "aws_kms_key" "existing" {
  count  = !try(var.settings.kms.enabled, true) && try(var.settings.kms.key_id, "") != "" ? 1 : 0
  key_id = var.settings.kms.key_id
}

resource "aws_kms_key" "this" {
  count                   = local.kms_create ? 1 : 0
  description             = "KMS Key for SSM Documents managed by Session Management Module"
  deletion_window_in_days = try(var.settings.kms.deletion_window, 30)
  enable_key_rotation     = try(var.settings.kms.enable_key_rotation, true)
  rotation_period_in_days = try(var.settings.kms.rotation_period_in_days, 90)
  multi_region            = try(var.settings.kms.multi_region, false)
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key-default-1"
    Statement = concat([
      {
        Sid    = "AllowRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }],
      local.cloudwatch_enabled ? [{
        Sid    = "AllowCloudWatchLogsAccess"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.audit_log_group_name}"
          }
        }
      }] : [],
      # Resource data sync writes Inventory data as the service principal rather than as a
      # role in this account, so the key policy has to grant it directly.
      local.resource_data_sync_uses_module_key ? [{
        Sid    = "AllowSSMResourceDataSyncAccess"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }] : [],
      # GUI Connect writes the finished RDP recording into the audit bucket, so it needs to
      # encrypt with the bucket's key. Scoped through kms:ViaService so the grant only
      # applies to calls S3 makes on its behalf, never to direct use of the key.
      local.rdp_recording_needs_bucket_key_grant ? [{
        Sid    = "AllowGuiConnectRecordingAccessViaS3"
        Effect = "Allow"
        Principal = {
          Service = "ssm-guiconnect.amazonaws.com"
        }
        Action   = "kms:GenerateDataKey*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          StringLike = {
            "kms:ViaService" = "s3.${data.aws_region.current.region}.amazonaws.com"
          }
        }
      }] : [],
      local.has_allowed_iam_roles ? [{
        Sid    = "AllowIAMRolesAccess"
        Effect = "Allow"
        Principal = {
          AWS = local.allowed_iam_role_arns
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
      }] : [],
      # The bucket is SSE-KMS encrypted, so S3 actions on their own cannot read an object body or
      # write a new one. Administrative roles get the same data plane actions as the roles
      # above -- deliberately not kms:*, which would let them rewrite this policy or
      # schedule the key for deletion.
      local.has_admin_iam_roles ? [{
        Sid    = "AllowIAMAdminRolesAccess"
        Effect = "Allow"
        Principal = {
          AWS = local.admin_iam_role_arns
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
      }] : []
    )
  })
  # RDP recording is a just-in-time node access feature, and the operator policy AWS
  # documents allows kms:CreateGrant only on keys carrying this tag. Without it an operator
  # cannot start a recorded connection even once recording preferences are set.
  tags = merge(
    local.all_tags,
    local.rdp_recording_uses_module_key ? { SystemsManagerJustInTimeNodeAccessManaged = "true" } : {}
  )
}

resource "aws_kms_alias" "this" {
  count         = local.kms_create ? 1 : 0
  target_key_id = aws_kms_key.this[0].key_id
  name          = format("alias/%s", try(var.settings.kms.alias_name, "ssm-session-mgmt-key-${local.system_name}"))
}
