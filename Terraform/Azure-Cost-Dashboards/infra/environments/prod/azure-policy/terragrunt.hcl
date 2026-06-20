include "root"      { path = find_in_parent_folders() }
include "envcommon" { path = "${dirname(find_in_parent_folders())}/_envcommon/azure-policy.hcl" expose = true }
include "env"       { path = "${dirname(find_in_parent_folders())}/env.hcl" expose = true }

# No dependencies needed, policies apply at the subscription level

inputs = {
  # Apply the policy to the Prod Subscription
  scope_id = "/subscriptions/${get_env("ARM_SUBSCRIPTION_ID")}"
}