mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_organizations_organization" {
    defaults = {
      roots = [{
        arn          = "arn:aws:organizations::123456789012:root/o-abcdefghij/r-abcd"
        id           = "r-abcd"
        name         = "Root"
        policy_types = []
      }]
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/mock"
    }
  }
}

mock_provider "awscc" {
  mock_data "awscc_ssmquicksetup_configuration_manager" {
    defaults = {
      status_summaries = [{
        last_updated_at = "2026-11-27T12:00:00Z"
        status          = "SUCCEEDED"
        status_details  = {}
        status_message  = ""
        status_type     = "Deployment"
      }]
    }
  }
}
mock_provider "random" {}

variables {
  org = {
    organization_name = "example"
    organization_unit = "ops"
    environment_type  = "prod"
    environment_name  = "shared"
  }
}

run "defaults_leave_fleet_access_disabled" {
  command = plan

  assert {
    condition = (
      length(awscc_ssmquicksetup_configuration_manager.unified_console) == 0 &&
      length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 0 &&
      length(awscc_ssmguiconnect_preferences.remote_desktop) == 0 &&
      output.unified_console_quicksetup_manager_arn == ""
    )
    error_message = "Unified console, JIT node access, and recording must be opt-in."
  }
}

run "enable_jit_without_recording" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        remote_desktop = {
          just_in_time_node_access = { enabled = true }
        }
      }
    }
  }

  assert {
    condition     = length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 1 && length(awscc_ssmguiconnect_preferences.remote_desktop) == 0
    error_message = "JIT node access must create a configuration independently of RDP recording."
  }

  assert {
    condition     = length(data.awscc_ssmquicksetup_configuration_manager.unified_console) == 1
    error_message = "Managed console deployment must be read before enabling JIT."
  }

  assert {
    condition     = length(aws_iam_role.jit_node_access_administration) == 1 && length(aws_iam_role.jit_node_access_execution) == 1
    error_message = "Single-account deployment must provision both Quick Setup deployment roles by default."
  }

  assert {
    condition = (
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).type == "AWSQuickSetupType-SSM" &&
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).parameters == tomap({
        AgentUpdateSchedule         = "none"
        EnableDHMCSchedule          = "none"
        InventoryCollectionSchedule = "none"
        DelegatedAccountId          = "123456789012"
        HomeRegion                  = "us-east-1"
        TargetAccounts              = "123456789012"
        TargetRegions               = "us-east-1"
      })
    )
    error_message = "JIT must deploy a local unified console without taking over host management, inventory, or agent updates."
  }

  assert {
    condition = toset(keys(aws_iam_role_policy_attachment.jit_node_access_execution)) == toset([
      "arn:aws:iam::aws:policy/AWSQuickSetupDeploymentRolePolicy",
      "arn:aws:iam::aws:policy/AWSQuickSetupJITNADeploymentRolePolicy",
      "arn:aws:iam::aws:policy/AWSQuickSetupSSMDeploymentRolePolicy",
    ])
    error_message = "The shared execution role must grant deployment permissions for JIT and the unified console."
  }

  assert {
    condition = (
      length(aws_ssm_service_setting.default_host_management) == 0 &&
      length(aws_ssm_association.inventory) == 0 &&
      length(aws_ssmquicksetup_configuration_manager.host) == 0 &&
      length(aws_ssmquicksetup_configuration_manager.patch) == 0 &&
      length(aws_ssmquicksetup_configuration_manager.dhmc) == 0
    )
    error_message = "Enabling JIT alone must leave host management, inventory and patching available to another owner."
  }

  assert {
    condition     = lookup(aws_kms_key.this[0].tags, "SystemsManagerJustInTimeNodeAccessManaged", "") == "true"
    error_message = "The module-created session key must be eligible for the JIT operator's KMS grant."
  }

  assert {
    condition = one(awscc_ssmquicksetup_configuration_manager.jit_node_access[0].configuration_definitions).type == "AWSQuickSetupType-JITNA" && one(awscc_ssmquicksetup_configuration_manager.jit_node_access[0].configuration_definitions).parameters == tomap({
      DelegatedAccountId      = "123456789012"
      HomeRegion              = "us-east-1"
      IdentityProviderSetting = "IAM"
      TargetAccounts          = "123456789012"
      TargetRegions           = "us-east-1"
    })
    error_message = "Single-account Quick Setup must send the JIT configuration type, current account and Region, and IAM identity provider."
  }
}

run "enable_jit_for_organization" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        remote_desktop = {
          just_in_time_node_access = {
            enabled                     = true
            organization_level          = true
            create_deployment_roles     = false
            target_organizational_units = "ou-abcd-11111111"
            target_regions              = "us-east-1,us-west-2"
            home_region                 = "us-west-2"
            identity_provider           = "SSO"
          }
        }
      }
    }
  }

  assert {
    condition     = length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 1 && length(aws_iam_role.jit_node_access_administration) == 0 && length(aws_iam_role.jit_node_access_execution) == 0
    error_message = "Organization JIT can use Quick Setup service-managed deployment without local role creation."
  }

  assert {
    condition = one(awscc_ssmquicksetup_configuration_manager.jit_node_access[0].configuration_definitions).parameters == tomap({
      DelegatedAccountId        = "123456789012"
      HomeRegion                = "us-west-2"
      IdentityProviderSetting   = "SSO"
      TargetOrganizationalUnits = "ou-abcd-11111111"
      TargetRegions             = "us-east-1,us-west-2"
    })
    error_message = "Organization JIT must use the requested OU, Regions, and SSO identity provider."
  }

  assert {
    condition = (
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).parameters == tomap({
        AgentUpdateSchedule         = "none"
        EnableDHMCSchedule          = "none"
        InventoryCollectionSchedule = "none"
        DelegatedAccountId          = "123456789012"
        HomeRegion                  = "us-west-2"
        TargetOrganizationalUnits   = "r-abcd"
        TargetRegions               = "us-east-1,us-west-2"
      })
    )
    error_message = "Organization console must target the organization root with JIT's home and target Regions."
  }
}

run "record_with_standalone_jit_settings" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        remote_desktop = {
          just_in_time_node_access = { enabled = true }
          recording                = { enabled = true }
        }
      }
    }
  }

  assert {
    condition     = length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 1 && length(awscc_ssmguiconnect_preferences.remote_desktop) == 1
    error_message = "Canonical JIT settings must satisfy the recording prerequisite."
  }
}

run "keep_legacy_nested_recording_jit" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        remote_desktop = {
          just_in_time_node_access = null
          recording = {
            enabled                  = true
            just_in_time_node_access = { enabled = true }
          }
        }
      }
    }
  }

  assert {
    condition     = length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 1 && length(awscc_ssmguiconnect_preferences.remote_desktop) == 1
    error_message = "Existing nested recording settings must still enable JIT and recording."
  }
}

run "keep_legacy_flat_recording_jit" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        remote_desktop = {
          recording = {
            enabled                          = true
            just_in_time_node_access_enabled = true
          }
        }
      }
    }
  }

  assert {
    condition     = length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 1 && length(awscc_ssmguiconnect_preferences.remote_desktop) == 1
    error_message = "Existing flat recording settings must still enable JIT and recording."
  }
}

run "legacy_jit_follows_recording" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        remote_desktop = {
          recording = {
            enabled                          = false
            just_in_time_node_access_enabled = true
            just_in_time_node_access         = { enabled = true }
          }
        }
      }
    }
  }

  assert {
    condition     = length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 0 && length(awscc_ssmguiconnect_preferences.remote_desktop) == 0
    error_message = "Legacy recording settings must not activate paid JIT when recording is off."
  }
}

run "delegation_leaves_jit_disabled" {
  command = plan

  variables {
    settings = {
      organization = {
        delegated  = true
        account_id = "123456789012"
      }
      fleet_manager = {
        enabled         = true
        unified_console = { enabled = true }
        remote_desktop = {
          just_in_time_node_access = { enabled = true }
        }
      }
    }
  }

  assert {
    condition = (
      length(aws_organizations_delegated_administrator.this) == 1 &&
      length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 0 &&
      length(awscc_ssmquicksetup_configuration_manager.unified_console) == 0
    )
    error_message = "Delegation mode must register the administrator and skip console and JIT configuration."
  }
}

run "reject_recording_when_canonical_jit_overrides_legacy" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        remote_desktop = {
          just_in_time_node_access = { enabled = false }
          recording = {
            enabled                          = true
            just_in_time_node_access_enabled = true
          }
        }
      }
    }
  }

  expect_failures = [awscc_ssmguiconnect_preferences.remote_desktop]
}

run "reject_jit_organization_without_ou" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        remote_desktop = {
          just_in_time_node_access = { enabled = true, organization_level = true }
        }
      }
    }
  }

  expect_failures = [awscc_ssmquicksetup_configuration_manager.jit_node_access]
}

run "reject_invalid_jit_identity_provider" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        remote_desktop = {
          just_in_time_node_access = { enabled = true, identity_provider = "INVALID" }
        }
      }
    }
  }

  expect_failures = [awscc_ssmquicksetup_configuration_manager.jit_node_access]
}

run "reject_recording_to_audit_bucket_without_customer_key" {
  command = plan

  variables {
    settings = {
      kms = { enabled = false }
      fleet_manager = {
        enabled = true
        remote_desktop = {
          just_in_time_node_access = { enabled = true }
          recording = {
            enabled     = true
            kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
          }
        }
      }
    }
  }

  expect_failures = [awscc_ssmguiconnect_preferences.remote_desktop]
}

run "enable_jit_with_existing_deployment_roles" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        remote_desktop = {
          just_in_time_node_access = {
            enabled                  = true
            create_deployment_roles  = false
            administration_role_name = "existing-quicksetup-admin"
            execution_role_name      = "existing-quicksetup-execution"
          }
        }
      }
    }
  }

  assert {
    condition     = length(aws_iam_role.jit_node_access_administration) == 0 && length(aws_iam_role.jit_node_access_execution) == 0
    error_message = "Reusing Quick Setup roles must leave their IAM resources external."
  }

  assert {
    condition = (
      one(awscc_ssmquicksetup_configuration_manager.jit_node_access[0].configuration_definitions).local_deployment_administration_role_arn == "arn:aws:iam::123456789012:role/existing-quicksetup-admin" &&
      one(awscc_ssmquicksetup_configuration_manager.jit_node_access[0].configuration_definitions).local_deployment_execution_role_name == "existing-quicksetup-execution"
    )
    error_message = "Single-account deployment must pass the configured Quick Setup role identifiers."
  }
}

run "use_existing_unified_console" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled         = true
        unified_console = { enabled = false }
        remote_desktop = {
          just_in_time_node_access = { enabled = true }
        }
      }
    }
  }

  assert {
    condition = (
      length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 1 &&
      length(awscc_ssmquicksetup_configuration_manager.unified_console) == 0 &&
      output.unified_console_quicksetup_manager_arn == "" &&
      length(data.awscc_ssmquicksetup_configuration_manager.unified_console) == 0 &&
      !contains(keys(aws_iam_role_policy_attachment.jit_node_access_execution), "arn:aws:iam::aws:policy/AWSQuickSetupSSMDeploymentRolePolicy")
    )
    error_message = "An explicit console opt-out must leave the existing console external and preserve JIT deployment."
  }
}

run "enable_unified_console_without_jit" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        unified_console = {
          enabled                       = true
          agent_update_schedule         = "rate(14 days)"
          enable_dhmc_schedule          = "rate(1 day)"
          inventory_collection_schedule = "rate(1 day)"
        }
      }
    }
  }

  assert {
    condition = (
      length(awscc_ssmquicksetup_configuration_manager.unified_console) == 1 &&
      length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 0 &&
      toset(keys(aws_iam_role_policy_attachment.jit_node_access_execution)) == toset([
        "arn:aws:iam::aws:policy/AWSQuickSetupDeploymentRolePolicy",
        "arn:aws:iam::aws:policy/AWSQuickSetupSSMDeploymentRolePolicy",
      ])
    )
    error_message = "A standalone console must deploy with console permissions and no JIT resources or policy."
  }

  assert {
    condition = one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).parameters == tomap({
      AgentUpdateSchedule         = "rate(14 days)"
      EnableDHMCSchedule          = "rate(1 day)"
      InventoryCollectionSchedule = "rate(1 day)"
      DelegatedAccountId          = "123456789012"
      HomeRegion                  = "us-east-1"
      TargetAccounts              = "123456789012"
      TargetRegions               = "us-east-1"
    })
    error_message = "The unified console must send the opted-in schedules to Quick Setup."
  }
}

run "reject_unified_console_missing_jit_region" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        unified_console = {
          organization_root_id = "r-wxyz"
          target_regions       = "us-east-1"
        }
        remote_desktop = {
          just_in_time_node_access = {
            enabled                     = true
            organization_level          = true
            create_deployment_roles     = false
            target_organizational_units = "ou-abcd-11111111"
            target_regions              = "us-east-1,us-west-2"
          }
        }
      }
    }
  }

  expect_failures = [awscc_ssmquicksetup_configuration_manager.unified_console]
}

run "preserve_imported_organization_console_settings" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        unified_console = {
          name                  = "existing-unified-console"
          description           = "Existing organization configuration"
          type_version          = "1.0"
          organization_root_id  = "r-wxyz"
          target_regions        = "us-east-1,us-west-2,eu-west-1"
          additional_parameters = { ExistingSetting = "preserved" }
        }
        remote_desktop = {
          just_in_time_node_access = {
            enabled                     = true
            organization_level          = true
            create_deployment_roles     = false
            administration_role_name    = "existing-quicksetup-admin"
            execution_role_name         = "existing-quicksetup-execution"
            target_organizational_units = "ou-abcd-11111111"
            target_regions              = "us-east-1,us-west-2"
          }
        }
      }
    }
  }

  assert {
    condition = (
      length(data.aws_organizations_organization.unified_console) == 0 &&
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).parameters["TargetOrganizationalUnits"] == "r-wxyz" &&
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).parameters["TargetRegions"] == "us-east-1,us-west-2,eu-west-1"
    )
    error_message = "Explicit root and wider console Region coverage must be accepted without a root lookup."
  }

  assert {
    condition = (
      awscc_ssmquicksetup_configuration_manager.unified_console[0].name == "existing-unified-console" &&
      awscc_ssmquicksetup_configuration_manager.unified_console[0].description == "Existing organization configuration" &&
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).type_version == "1.0" &&
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).parameters["ExistingSetting"] == "preserved"
    )
    error_message = "Adoption must preserve the console's name, description, version, and additional parameters."
  }

  assert {
    condition = (
      length(aws_iam_role.jit_node_access_administration) == 0 &&
      length(aws_iam_role.jit_node_access_execution) == 0 &&
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).local_deployment_administration_role_arn == "arn:aws:iam::123456789012:role/existing-quicksetup-admin" &&
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).local_deployment_execution_role_name == "existing-quicksetup-execution"
    )
    error_message = "An imported organization console must retain explicitly configured external deployment roles."
  }
}

run "reject_single_account_console_in_another_region" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        unified_console = {
          enabled        = true
          target_regions = "us-east-1,us-west-2"
        }
      }
    }
  }

  expect_failures = [awscc_ssmquicksetup_configuration_manager.unified_console]
}

run "use_separate_console_deployment_roles" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        unified_console = {
          deployment_roles = {
            administration_role_arn = "arn:aws:iam::123456789012:role/existing-console-admin"
            execution_role_name     = "existing-console-execution"
          }
        }
        remote_desktop = {
          just_in_time_node_access = {
            enabled                  = true
            administration_role_name = "jit-admin"
            execution_role_name      = "jit-execution"
          }
        }
      }
    }
  }

  assert {
    condition = (
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).local_deployment_administration_role_arn == "arn:aws:iam::123456789012:role/existing-console-admin" &&
      one(awscc_ssmquicksetup_configuration_manager.unified_console[0].configuration_definitions).local_deployment_execution_role_name == "existing-console-execution" &&
      one(awscc_ssmquicksetup_configuration_manager.jit_node_access[0].configuration_definitions).local_deployment_administration_role_arn == "arn:aws:iam::123456789012:role/jit-admin" &&
      one(awscc_ssmquicksetup_configuration_manager.jit_node_access[0].configuration_definitions).local_deployment_execution_role_name == "jit-execution"
    )
    error_message = "The imported console and JIT must each use their own deployment roles."
  }

  assert {
    condition = toset(keys(aws_iam_role_policy_attachment.jit_node_access_execution)) == toset([
      "arn:aws:iam::aws:policy/AWSQuickSetupDeploymentRolePolicy",
      "arn:aws:iam::aws:policy/AWSQuickSetupJITNADeploymentRolePolicy",
    ])
    error_message = "Independent console roles must leave the JIT execution role's policy set unchanged."
  }
}

run "omit_organization_console_roles_when_jit_manages_roles" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled         = true
        unified_console = { deployment_roles = {} }
        remote_desktop = {
          just_in_time_node_access = {
            enabled                     = true
            organization_level          = true
            target_organizational_units = "ou-abcd-11111111"
          }
        }
      }
    }
  }

  assert {
    condition = (
      local.console_admin_role_arn == null &&
      local.console_execution_role == null &&
      length(aws_iam_role.jit_node_access_administration) == 1 &&
      length(aws_iam_role.jit_node_access_execution) == 1 &&
      !contains(keys(aws_iam_role_policy_attachment.jit_node_access_execution), "arn:aws:iam::aws:policy/AWSQuickSetupSSMDeploymentRolePolicy")
    )
    error_message = "An explicit empty console role override must preserve service-managed console roles and JIT-owned roles."
  }
}

run "reject_partial_unified_console_role_pair" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        unified_console = {
          enabled          = true
          deployment_roles = { execution_role_name = "existing-console-execution" }
        }
      }
    }
  }

  expect_failures = [awscc_ssmquicksetup_configuration_manager.unified_console]
}

run "reject_unified_console_additional_target_parameter" {
  command = plan

  variables {
    settings = {
      fleet_manager = {
        enabled = true
        unified_console = {
          enabled               = true
          additional_parameters = { TargetOrganizationalUnits = "r-wxyz" }
        }
      }
    }
  }

  expect_failures = [awscc_ssmquicksetup_configuration_manager.unified_console]
}
