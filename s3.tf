##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  audit_s3_key_prefix = try(var.settings.audit.s3_key_prefix, "session-manager/")

  bucket_name_override = try(var.settings.bucket.name, "")

  # settings.random_bucket_suffix is the legacy spelling kept for backwards
  # compatibility; settings.bucket.random_suffix takes precedence when both are set.
  bucket_random_suffix = try(var.settings.bucket.random_suffix, try(var.settings.random_bucket_suffix, true))

  create_bucket_suffix = local.bucket_random_suffix && local.bucket_name_override == "" && !local.is_delegated

  ssm_logs_bucket_prefix = "ssm-session-auditlogs-${local.system_name}"

  ssm_logs_bucket = local.bucket_name_override != "" ? local.bucket_name_override : join("", concat(
    [local.ssm_logs_bucket_prefix],
    local.create_bucket_suffix ? ["-"] : [],
    random_string.random[*].result
  ))

  # Deterministic length of the generated name; the random suffix always contributes
  # exactly 9 characters ("-" plus 8 random). Used to guard the 63 character S3 limit
  # without waiting for the random value to be known.
  ssm_logs_bucket_length = local.bucket_name_override != "" ? length(local.bucket_name_override) : length(local.ssm_logs_bucket_prefix) + (local.create_bucket_suffix ? 9 : 0)

  s3_kms_key_arn = local.has_kms_key ? local.kms_key_arn : "arn:${data.aws_partition.current.partition}:kms:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:alias/aws/s3"

  audit_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}"
  audit_bucket_and_objects = [
    local.audit_bucket_arn,
    "${local.audit_bucket_arn}/*",
  ]

  attach_bucket_policy = (
    local.has_allowed_iam_roles ||
    local.has_admin_iam_roles ||
    local.resource_data_sync_uses_audit_bucket ||
    local.rdp_recording_uses_audit_bucket
  )
}

data "aws_iam_policy_document" "audit_bucket" {
  dynamic "statement" {
    for_each = local.has_allowed_iam_roles ? [1] : []
    content {
      sid       = "AllowIAMRolesAccess"
      actions   = ["s3:PutObject", "s3:GetEncryptionConfiguration"]
      resources = local.audit_bucket_and_objects

      principals {
        type        = "AWS"
        identifiers = local.allowed_role_principals
      }
    }
  }

  # Enumerate the object and listing operations so administrators can manage recordings
  # without changing the audit bucket policy or encryption, or deleting the bucket.
  dynamic "statement" {
    for_each = local.has_admin_iam_roles ? [1] : []
    content {
      sid = "AllowIAMAdminRolesAccess"
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetObjectAttributes",
        "s3:GetObjectVersionAttributes",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
        "s3:ListBucketMultipartUploads",
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:GetBucketLocation",
        "s3:GetEncryptionConfiguration",
      ]
      resources = local.audit_bucket_and_objects

      principals {
        type        = "AWS"
        identifiers = local.admin_role_principals
      }
    }
  }

  # SSM delivers Inventory as a service principal.
  dynamic "statement" {
    for_each = local.resource_data_sync_uses_audit_bucket ? [1] : []
    content {
      sid       = "SSMBucketPermissionsCheck"
      actions   = ["s3:GetBucketAcl"]
      resources = [local.audit_bucket_arn]

      principals {
        type        = "Service"
        identifiers = ["ssm.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.resource_data_sync_uses_audit_bucket ? [1] : []
    content {
      sid       = "SSMBucketDelivery"
      actions   = ["s3:PutObject"]
      resources = [replace(local.resource_data_sync_object_pattern, "{", local.escaped_policy_brace)]

      principals {
        type        = "Service"
        identifiers = ["ssm.amazonaws.com"]
      }

      # The bucket disables ACLs. Scope writes to this account's resource data sync.
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:resource-data-sync/*"]
      }
    }
  }

  # GUI Connect recording preferences provide a bucket without an object prefix.
  dynamic "statement" {
    for_each = local.rdp_recording_uses_audit_bucket ? [1] : []
    content {
      sid       = "ConnectionRecording"
      actions   = ["s3:PutObject"]
      resources = local.audit_bucket_and_objects

      principals {
        type        = "Service"
        identifiers = ["ssm-guiconnect.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }
}

resource "random_string" "random" {
  count   = local.create_bucket_suffix ? 1 : 0
  length  = 8
  special = false
  lower   = true
  upper   = false
  numeric = true
}

module "ssm_bucket" {
  source                                = "terraform-aws-modules/s3-bucket/aws"
  version                               = "~> 5.10"
  create_bucket                         = !local.is_delegated
  bucket                                = local.ssm_logs_bucket
  block_public_acls                     = true
  block_public_policy                   = true
  ignore_public_acls                    = true
  restrict_public_buckets               = true
  attach_public_policy                  = true
  attach_require_latest_tls_policy      = true
  attach_deny_insecure_transport_policy = true
  attach_policy                         = local.attach_bucket_policy
  policy                                = local.attach_bucket_policy ? replace(data.aws_iam_policy_document.audit_bucket.json, local.escaped_policy_brace, "{") : null

  # BucketOwnerEnforced, not BucketOwnerPreferred. Under Preferred the bucket owner only
  # takes ownership of an object when the uploader sets the bucket-owner-full-control ACL,
  # and Fleet Manager Remote Desktop recordings are uploaded by the GUI Connect service
  # without one. Those recordings stayed owned by an AWS service account, and a bucket
  # policy cannot grant access to objects the bucket owner does not own -- so the account
  # paying for the bucket could never read its own recordings, whatever the policy said.
  # Enforced disables ACLs outright and makes the bucket owner own every object.
  #
  # No "acl" argument here on purpose: the upstream module creates an aws_s3_bucket_acl
  # whenever acl is non-null, and setting an ACL on an enforced-ownership bucket fails with
  # AccessControlListNotSupported.
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  versioning = {
    enabled = try(var.settings.bucket.versioning, false)
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = local.s3_kms_key_arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule = [
    {
      id      = "audit-log-lifecycle-policy"
      enabled = true

      # Scoped to the session log prefix so that other data sharing this bucket — Fleet
      # Manager Inventory delivered by resource data sync, which has to stay in a queryable
      # storage class — is not archived or expired by the session log retention policy.
      filter = {
        prefix = local.audit_s3_key_prefix
      }

      abort_incomplete_multipart_upload_days = try(var.settings.audit.abort_multipart_days, 7)

      transition = [
        {
          days          = try(var.settings.audit.transition_days, 30)
          storage_class = "STANDARD_IA"
        },
        {
          days          = try(var.settings.audit.archive_days, 60)
          storage_class = "GLACIER"
        }
      ]

      expiration = {
        days = try(var.settings.audit.retention_years * 365, 5 * 365)
      }
    }
  ]
  tags = local.all_tags
}
