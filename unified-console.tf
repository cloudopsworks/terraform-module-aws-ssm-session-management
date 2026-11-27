##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  unified_console         = try(var.settings.fleet_manager.unified_console, {})
  unified_console_enabled = local.fleet_manager_enabled && coalesce(try(local.unified_console.enabled, null), local.jit_node_access_enabled)

  unified_console_regions   = coalesce(try(local.unified_console.target_regions, null), local.jit_target_regions)
  console_diagnosis_regions = toset([for region in concat([local.jit_home_region], split(",", local.unified_console_regions)) : trimspace(region)])
  console_root_override     = try(coalesce(local.unified_console.organization_root_id), "")
  unified_console_root_id   = local.console_root_override != "" ? local.console_root_override : try(data.aws_organizations_organization.unified_console[0].roots[0].id, "")

  # A console enabled before JIT may have its own pair of deployment roles.
  console_role_override  = try(local.unified_console.deployment_roles, null)
  console_uses_jit_roles = local.unified_console_enabled && local.console_role_override == null
  console_named_roles    = try(local.jit_node_access.administration_role_name, "") != "" && try(local.jit_node_access.execution_role_name, "") != ""
  console_default_roles = local.jit_pass_deployment_roles || local.console_named_roles ? {
    administration_role_arn = local.jit_administration_role_arn
    execution_role_name     = local.jit_execution_role_name
  } : null
  console_roles          = local.console_role_override != null ? local.console_role_override : local.console_default_roles
  console_admin_role_arn = try(local.console_roles.administration_role_arn, null)
  console_execution_role = try(local.console_roles.execution_role_name, null)

  console_delegated_account_id = try(trimspace(local.unified_console.delegated_account_id), "")
  console_extra_parameters     = coalesce(try(local.unified_console.additional_parameters, null), {})

  unified_console_parameters = merge({
    HomeRegion                  = local.jit_home_region
    TargetRegions               = local.unified_console_regions
    AgentUpdateSchedule         = coalesce(try(local.unified_console.agent_update_schedule, null), "rate(14 days)")
    EnableDHMCSchedule          = coalesce(try(local.unified_console.enable_dhmc_schedule, null), "rate(1 day)")
    InventoryCollectionSchedule = coalesce(try(local.unified_console.inventory_collection_schedule, null), "rate(12 hours)")
    },
    local.console_delegated_account_id != "" ? { DelegatedAccountId = local.console_delegated_account_id } : {},
    local.jit_organization_level ? { TargetOrganizationalUnits = local.unified_console_root_id } : { TargetAccounts = data.aws_caller_identity.current.account_id },
  )
}

data "aws_organizations_organization" "unified_console" {
  count = local.unified_console_enabled && local.jit_organization_level && local.console_root_override == "" ? 1 : 0
}

# The SSM deployment policy grants TagRole on diagnosis roles but omits UntagRole.
resource "awscc_iam_role_policy" "console_diagnosis_untag" {
  count       = local.console_uses_jit_roles && local.jit_create_deployment_roles ? 1 : 0
  role_name   = aws_iam_role.jit_node_access_execution[0].name
  policy_name = "QuickSetupSSMDiagnosisAdminUntag"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "iam:UntagRole"
      Resource = [
        for region in local.console_diagnosis_regions :
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/AWS-SSM-DiagnosisAdminRole-${data.aws_caller_identity.current.account_id}-${region}"
      ]
    }]
  })

  lifecycle {
    precondition {
      condition     = alltrue([for region in local.console_diagnosis_regions : can(regex("^[a-z0-9-]+$", region))])
      error_message = "Use literal AWS Region names for the unified console home and target Regions so the IAM policy can name each diagnosis role exactly."
    }
  }
}

resource "awscc_ssmquicksetup_configuration_manager" "unified_console" {
  count       = local.unified_console_enabled ? 1 : 0
  name        = coalesce(try(local.unified_console.name, null), "${local.system_name}-ssm-console")
  description = try(local.unified_console.description, null)
  tags        = local.all_tags

  configuration_definitions = [{
    type                                     = "AWSQuickSetupType-SSM"
    type_version                             = try(coalesce(local.unified_console.type_version), null)
    local_deployment_administration_role_arn = local.console_admin_role_arn
    local_deployment_execution_role_name     = local.console_execution_role
    parameters                               = merge(local.console_extra_parameters, local.unified_console_parameters)
  }]

  depends_on = [
    aws_iam_role_policy.jit_node_access_administration,
    aws_iam_role_policy_attachment.jit_node_access_execution,
    awscc_iam_role_policy.console_diagnosis_untag,
  ]

  lifecycle {
    precondition {
      condition = (
        (local.jit_organization_level && local.console_admin_role_arn == null && local.console_execution_role == null) ||
        (try(length(local.console_admin_role_arn) > 0, false) && try(length(local.console_execution_role) > 0, false))
      )
      error_message = "Set both unified_console.deployment_roles.administration_role_arn and execution_role_name when supplying console roles. Only an organization deployment can omit both."
    }

    precondition {
      condition     = !local.jit_organization_level || can(regex("^r-[a-z0-9]{4,32}$", local.unified_console_root_id))
      error_message = "Organization console setup requires the organization root. Set unified_console.organization_root_id if the provider cannot discover it."
    }

    precondition {
      condition = local.jit_organization_level || (
        local.unified_console_regions == local.jit_home_region &&
        local.jit_target_accounts == data.aws_caller_identity.current.account_id &&
        (local.console_delegated_account_id == "" || local.console_delegated_account_id == data.aws_caller_identity.current.account_id)
      )
      error_message = "A single-account unified console targets the current account and one Region. Use the same home and target Region and, if supplying a console delegated account, use the current account."
    }

    precondition {
      condition     = !local.jit_node_access_enabled || length(setsubtract(split(",", local.jit_target_regions), split(",", local.unified_console_regions))) == 0
      error_message = "unified_console.target_regions must cover every JIT target Region."
    }

    precondition {
      condition     = length(setintersection(keys(local.console_extra_parameters), concat(keys(local.unified_console_parameters), ["TargetAccounts", "TargetOrganizationalUnits", "DelegatedAccountId"]))) == 0
      error_message = "Use the dedicated settings for console targets, home Region, delegated account and schedules. additional_parameters is for other Quick Setup parameters."
    }
  }
}

# AWSCC can carry the old status forward during an update. Read the deployed manager
# after the change so JIT checks the current deployment.
data "awscc_ssmquicksetup_configuration_manager" "unified_console" {
  count = local.jit_node_access_enabled && local.unified_console_enabled ? 1 : 0
  id    = awscc_ssmquicksetup_configuration_manager.unified_console[0].manager_arn

  depends_on = [awscc_ssmquicksetup_configuration_manager.unified_console]
}
