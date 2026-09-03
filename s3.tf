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

  # Two independent reasons to attach a bucket policy, so the statements are assembled as a
  # list and the policy is only attached when at least one of them applies.
  bucket_policy_statements = concat(
    local.has_allowed_iam_roles ? [{
      Sid    = "AllowIAMRolesAccess"
      Effect = "Allow"
      Principal = {
        AWS = local.allowed_iam_role_arns
      }
      Action = [
        "s3:PutObject",
        "s3:GetEncryptionConfiguration",
      ]
      Resource = [
        "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}/*",
        "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}"
      ]
    }] : [],
    # Administrative roles get full object lifecycle on the bucket -- read, create, delete,
    # multipart and listing -- rather than the write-only pair above, so they can review and
    # clean up session logs and recordings. Deliberately enumerated rather than "s3:*":
    # the wildcard also carries s3:PutBucketPolicy, s3:DeleteBucketPolicy, s3:DeleteBucket
    # and s3:PutEncryptionConfiguration, which would let an audit reader rewrite this very
    # policy, drop the TLS denies, weaken the bucket's encryption or delete the bucket.
    local.has_admin_iam_roles ? [{
      Sid    = "AllowIAMAdminRolesAccess"
      Effect = "Allow"
      Principal = {
        AWS = local.admin_iam_role_arns
      }
      Action = [
        # Read
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetObjectAttributes",
        "s3:GetObjectVersionAttributes",
        # Create
        "s3:PutObject",
        # Delete
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        # Multipart, needed for and after large uploads such as RDP recordings
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
        "s3:ListBucketMultipartUploads",
        # List and discovery
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:GetBucketLocation",
        # Encryption discovery, so a client can resolve the bucket's CMK before writing
        "s3:GetEncryptionConfiguration",
      ]
      Resource = [
        "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}/*",
        "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}"
      ]
    }] : [],
    # Resource data sync delivers Inventory data as the service principal, not as a role in
    # this account, so it needs its own grant even though the bucket is account-owned. The
    # two statements are gated separately because they carry different shapes, and a single
    # conditional returning a two element tuple has no consistent type with the empty one.
    local.resource_data_sync_uses_audit_bucket ? [{
      Sid    = "SSMBucketPermissionsCheck"
      Effect = "Allow"
      Principal = {
        Service = "ssm.amazonaws.com"
      }
      Action   = "s3:GetBucketAcl"
      Resource = "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}"
    }] : [],
    local.resource_data_sync_uses_audit_bucket ? [{
      Sid    = "SSMBucketDelivery"
      Effect = "Allow"
      Principal = {
        Service = "ssm.amazonaws.com"
      }
      Action   = "s3:PutObject"
      Resource = local.resource_data_sync_object_pattern
      # No s3:x-amz-acl condition: ACLs are disabled on this bucket, and AWS documents that
      # requiring the canned ACL denies callers that correctly omit it. aws:SourceAccount
      # and aws:SourceArn remain the real constraints.
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:resource-data-sync/*"
        }
      }
    }] : [],
    # Fleet Manager Remote Desktop recordings are uploaded by the GUI Connect service
    # principal. The preferences schema carries no key prefix, so the grant has to cover the
    # bucket as a whole — which is also why the session log lifecycle rule above is scoped
    # to its own prefix rather than left bucket-wide.
    local.rdp_recording_uses_audit_bucket ? [{
      Sid    = "ConnectionRecording"
      Effect = "Allow"
      Principal = {
        Service = "ssm-guiconnect.amazonaws.com"
      }
      Action = "s3:PutObject"
      Resource = [
        "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}",
        "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}/*"
      ]
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }] : []
  )

  attach_bucket_policy = length(local.bucket_policy_statements) > 0
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
  policy = local.attach_bucket_policy ? jsonencode({
    Version   = "2012-10-17"
    Statement = local.bucket_policy_statements
  }) : null

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
