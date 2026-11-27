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

  kms_data_actions = [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
    "kms:Describe*",
  ]
}

data "aws_kms_alias" "existing" {
  count = !try(var.settings.kms.enabled, true) && try(var.settings.kms.key_alias, "") != "" ? 1 : 0
  name  = var.settings.kms.key_alias
}

data "aws_kms_key" "existing" {
  count  = !try(var.settings.kms.enabled, true) && try(var.settings.kms.key_id, "") != "" ? 1 : 0
  key_id = var.settings.kms.key_id
}

data "aws_iam_policy_document" "session_encryption" {
  count     = local.kms_create ? 1 : 0
  policy_id = "key-default-1"

  statement {
    sid       = "AllowRootAccountAccess"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = local.cloudwatch_enabled ? [1] : []
    content {
      sid       = "AllowCloudWatchLogsAccess"
      actions   = local.kms_data_actions
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
      }

      condition {
        test     = "ArnEquals"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.audit_log_group_name}"]
      }
    }
  }

  # SSM writes Inventory data as a service principal.
  dynamic "statement" {
    for_each = local.resource_data_sync_uses_module_key ? [1] : []
    content {
      sid       = "AllowSSMResourceDataSyncAccess"
      actions   = local.kms_data_actions
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["ssm.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  # GUI Connect encrypts recordings through S3 on the service principal's behalf.
  dynamic "statement" {
    for_each = local.rdp_recording_needs_bucket_key_grant ? [1] : []
    content {
      sid       = "AllowGuiConnectRecordingAccessViaS3"
      actions   = ["kms:GenerateDataKey*"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["ssm-guiconnect.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
      condition {
        test     = "StringLike"
        variable = "kms:ViaService"
        values   = ["s3.${data.aws_region.current.region}.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.has_allowed_iam_roles ? [1] : []
    content {
      sid       = "AllowIAMRolesAccess"
      actions   = local.kms_data_actions
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = local.allowed_role_principals
      }
    }
  }

  # Administrative roles use the key for object access without key policy or deletion privileges.
  dynamic "statement" {
    for_each = local.has_admin_iam_roles ? [1] : []
    content {
      sid       = "AllowIAMAdminRolesAccess"
      actions   = local.kms_data_actions
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = local.admin_role_principals
      }
    }
  }

  # Keep grant creation separate from ordinary key usage.
  dynamic "statement" {
    for_each = local.has_create_grant_iam_roles ? [1] : []
    content {
      sid       = "AllowIAMRolesCreateGrant"
      actions   = ["kms:CreateGrant"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = local.grant_role_principals
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count                   = local.kms_create ? 1 : 0
  description             = "KMS Key for SSM Documents managed by Session Management Module"
  deletion_window_in_days = try(var.settings.kms.deletion_window, 30)
  enable_key_rotation     = try(var.settings.kms.enable_key_rotation, true)
  rotation_period_in_days = try(var.settings.kms.rotation_period_in_days, 90)
  multi_region            = try(var.settings.kms.multi_region, false)
  policy                  = replace(data.aws_iam_policy_document.session_encryption[0].json, local.escaped_policy_brace, "{")

  # The JIT access token policy authorizes use of the tagged session encryption key.
  tags = merge(
    local.all_tags,
    local.jit_node_access_enabled ? { SystemsManagerJustInTimeNodeAccessManaged = "true" } : {}
  )
}

resource "aws_kms_alias" "this" {
  count         = local.kms_create ? 1 : 0
  target_key_id = aws_kms_key.this[0].key_id
  name          = format("alias/%s", try(var.settings.kms.alias_name, "ssm-session-mgmt-key-${local.system_name}"))
}
