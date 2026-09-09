##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

##
# Just-in-time node access setup.
#
# Fleet Manager Remote Desktop connection recording is a just-in-time node access feature:
# without JIT node access the recording preferences still apply, but every connection fails
# asynchronously with a 403 instead of producing a recording. AWS exposes the setup as the
# Quick Setup AWSQuickSetupType-JITNA configuration type, so this whole file is gated on
# local.rdp_recording_enabled -- nothing here exists for a module that is not recording.
#
# Quick Setup deploys the configuration through CloudFormation StackSets and therefore needs
# a pair of local deployment roles: an administration role CloudFormation assumes, and an
# execution role that administration role assumes in the target account. AWS names them
# AWS-QuickSetup-StackSet-Local-AdministrationRole and
# AWS-QuickSetup-StackSet-Local-ExecutionRole, and those names are kept so an account where
# Quick Setup has already run from the console keeps working -- turn create_deployment_roles
# off there rather than renaming, since IAM rejects a second role with the same name.
#
# The configuration manager itself goes through the awscc provider -- Quick Setup is only
# exposed via Cloud Control. The two deployment roles are ordinary IAM and are created with
# the aws provider, matching how every other role in this module is managed.
#
# The setup runs at one of two scopes, selected by organization_level: across organizational
# units, which is the default and must be applied from the Systems Manager delegated
# administrator account, or for the single account this module is applied in.
#
# PREREQUISITE this module does not create: the unified Systems Manager console
# (AWSQuickSetupType-SSM) must already be set up, covering at least the Regions targeted here
# -- JIT node access can only be enabled where the unified console is.
##
locals {
  jit_node_access = try(var.settings.fleet_manager.remote_desktop.recording.just_in_time_node_access, {})

  # Recording is the only consumer of just-in-time node access in this module, so the setup
  # follows the recording toggle exactly rather than carrying a second switch of its own.
  jit_node_access_enabled = local.rdp_recording_enabled

  # Quick Setup deploys into the organization from the Systems Manager delegated
  # administrator account. settings.organization.account_id already names that account when
  # the caller also runs this module in delegation mode from the management account;
  # otherwise the account this module is applied in is itself the delegated administrator.
  jit_delegated_account_id = try(local.jit_node_access.delegated_account_id, "") != "" ? local.jit_node_access.delegated_account_id : try(var.settings.organization.account_id, data.aws_caller_identity.current.account_id)

  # The Region the unified console aggregates into. JIT node access data follows it, so it
  # has to match the console's home Region rather than merely being a Region in the list.
  jit_home_region = try(local.jit_node_access.home_region, "") != "" ? local.jit_node_access.home_region : data.aws_region.current.region

  # AWS requires these to be the unified console target Regions or a subset of them.
  jit_target_regions = try(local.jit_node_access.target_regions, "") != "" ? local.jit_node_access.target_regions : data.aws_region.current.region

  # Just-in-time node access is set up either across organizational units, deployed from the
  # Systems Manager delegated administrator account, or for the single account this module is
  # applied in. The two take different Quick Setup target parameters, and AWS only lets the
  # local deployment roles be omitted for the organizational one, so the mode is explicit
  # rather than inferred from which target happens to be filled in.
  jit_organization_level = try(local.jit_node_access.organization_level, true)

  # Comma separated OU IDs. Required for an organization level setup and has no defensible
  # default; the precondition below rejects an empty one.
  jit_target_organizational_units = try(local.jit_node_access.target_organizational_units, "")

  # Comma separated account IDs for a single account setup. Defaults to the account this
  # module is applied in, which is the whole point of the mode.
  jit_target_accounts = try(local.jit_node_access.target_accounts, "") != "" ? local.jit_node_access.target_accounts : data.aws_caller_identity.current.account_id

  # Quick Setup rejects the target parameters that do not belong to the selected mode, so
  # only one of the two is ever sent.
  jit_targets = merge(
    { "TargetRegions" = local.jit_target_regions },
    local.jit_organization_level ? { "TargetOrganizationalUnits" = local.jit_target_organizational_units } : { "TargetAccounts" = local.jit_target_accounts },
  )

  # Decides where the approver identity behind an access request is read from: IAM reads the
  # principal starting the session, SSO the IAM Identity Center identity behind it.
  jit_identity_provider = try(local.jit_node_access.identity_provider, "IAM")

  jit_administration_role_name = try(local.jit_node_access.administration_role_name, "AWS-QuickSetup-StackSet-Local-AdministrationRole")
  jit_execution_role_name      = try(local.jit_node_access.execution_role_name, "AWS-QuickSetup-StackSet-Local-ExecutionRole")

  # Composed from the names rather than read back off the resources: the two roles reference
  # each other, and going through the resource attributes would be a dependency cycle. It
  # also lets the configuration manager point at roles Quick Setup created earlier.
  jit_administration_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.jit_administration_role_name}"
  jit_execution_role_arn      = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.jit_execution_role_name}"

  jit_create_deployment_roles = local.jit_node_access_enabled && try(local.jit_node_access.create_deployment_roles, true)

  # AWS lets the local deployment roles be omitted for an organization level deployment of any
  # type but a patch policy, and requires them for every single account deployment. They are
  # therefore passed whenever this module creates them, and always in single account mode --
  # but an organization level setup that reuses roles created elsewhere sends neither, rather
  # than naming roles this module cannot confirm exist.
  jit_pass_deployment_roles = local.jit_create_deployment_roles || !local.jit_organization_level

  # AWSQuickSetupDeploymentRolePolicy covers the StackSet plumbing every configuration type
  # shares but stops short of JIT node access: it grants nothing on the
  # AWSQuickSetupType-SetupJITNAResources document or the AWS-QuickSetup-EnableJITNA-* roles
  # the deployment creates. AWSQuickSetupJITNADeploymentRolePolicy is what covers those, so
  # both are attached.
  jit_execution_role_policy_arns = distinct(concat(
    [
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSQuickSetupDeploymentRolePolicy",
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSQuickSetupJITNADeploymentRolePolicy",
    ],
    try(local.jit_node_access.additional_policy_arns, []),
  ))
}

# CloudFormation assumes this role to drive the StackSet operation. The condition keys keep
# it usable only for Quick Setup's own stack sets in this account, so a confused deputy
# cannot borrow it for an unrelated stack set.
resource "aws_iam_role" "jit_node_access_administration" {
  count       = local.jit_create_deployment_roles ? 1 : 0
  name        = local.jit_administration_role_name
  path        = "/"
  description = "Quick Setup local deployment administration role assumed by CloudFormation to deploy just-in-time node access"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudformation.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudformation:*:${data.aws_caller_identity.current.account_id}:stackset/AWS-QuickSetup-*"
          }
        }
      }
    ]
  })
  tags = local.all_tags
}

# Kept as an inline policy on the administration role rather than a permission on the
# execution role: it is the administration role's only privilege, and scoping it to the one
# execution role ARN is what stops it assuming anything else.
resource "aws_iam_role_policy" "jit_node_access_administration" {
  count = local.jit_create_deployment_roles ? 1 : 0
  name  = "AssumeRole-AWSQuickSetupStackSetLocalExecutionRole"
  role  = aws_iam_role.jit_node_access_administration[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeLocalExecutionRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.jit_execution_role_arn
      }
    ]
  })
}

# The role the deployment actually runs as. It is deliberately assumable only by the
# administration role above, never by a service principal directly.
resource "aws_iam_role" "jit_node_access_execution" {
  count       = local.jit_create_deployment_roles ? 1 : 0
  name        = local.jit_execution_role_name
  path        = "/"
  description = "Quick Setup local deployment execution role used to deploy just-in-time node access"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = local.jit_administration_role_arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = local.all_tags
}

resource "aws_iam_role_policy_attachment" "jit_node_access_execution" {
  for_each   = local.jit_create_deployment_roles ? toset(local.jit_execution_role_policy_arns) : toset([])
  role       = aws_iam_role.jit_node_access_execution[0].name
  policy_arn = each.value
}

resource "awscc_ssmquicksetup_configuration_manager" "jit_node_access" {
  count       = local.jit_node_access_enabled ? 1 : 0
  name        = try(local.jit_node_access.name, "${local.system_name}-jitna")
  description = "SSM Quick Setup Configuration Manager for Just-in-Time Node Access ${local.system_name}"

  configuration_definitions = [
    {
      type                                     = "AWSQuickSetupType-JITNA"
      local_deployment_administration_role_arn = local.jit_pass_deployment_roles ? local.jit_administration_role_arn : null
      local_deployment_execution_role_name     = local.jit_pass_deployment_roles ? local.jit_execution_role_name : null

      parameters = merge({
        "DelegatedAccountId"      = local.jit_delegated_account_id
        "HomeRegion"              = local.jit_home_region
        "IdentityProviderSetting" = local.jit_identity_provider
        },
        local.jit_targets,
      )
    }
  ]

  tags = local.all_tags

  # Quick Setup validates the deployment roles as it starts the StackSet operation, and IAM
  # is eventually consistent, so the roles have to exist before the manager is created.
  depends_on = [
    aws_iam_role.jit_node_access_administration,
    aws_iam_role_policy.jit_node_access_administration,
    aws_iam_role.jit_node_access_execution,
    aws_iam_role_policy_attachment.jit_node_access_execution,
  ]

  lifecycle {
    precondition {
      condition     = !local.jit_organization_level || local.jit_target_organizational_units != ""
      error_message = "settings.fleet_manager.remote_desktop.recording.just_in_time_node_access.target_organizational_units is required for an organization level setup. Supply a comma separated list of organizational unit IDs, or the organization root ID to cover the whole organization -- or set organization_level to false to set just-in-time node access up for this account alone."
    }

    precondition {
      condition     = contains(["IAM", "SSO"], local.jit_identity_provider)
      error_message = "settings.fleet_manager.remote_desktop.recording.just_in_time_node_access.identity_provider must be either \"IAM\" or \"SSO\"."
    }
  }
}
