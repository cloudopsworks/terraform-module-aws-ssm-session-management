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

mock_provider "awscc" {}
mock_provider "random" {}

variables {
  org = {
    organization_name = "example"
    organization_unit = "ops"
    environment_type  = "prod"
    environment_name  = "shared"
  }
}

run "defaults_leave_jit_disabled" {
  command = plan

  assert {
    condition     = length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 0 && length(awscc_ssmguiconnect_preferences.remote_desktop) == 0
    error_message = "JIT node access and recording must be opt-in."
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
    condition     = length(aws_iam_role.jit_node_access_administration) == 1 && length(aws_iam_role.jit_node_access_execution) == 1
    error_message = "Single-account deployment must provision both Quick Setup deployment roles by default."
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
        enabled = true
        remote_desktop = {
          just_in_time_node_access = { enabled = true }
        }
      }
    }
  }

  assert {
    condition     = length(aws_organizations_delegated_administrator.this) == 1 && length(awscc_ssmquicksetup_configuration_manager.jit_node_access) == 0
    error_message = "Delegation mode must only register the administrator."
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
