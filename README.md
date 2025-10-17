<!--
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# 🔐 Credential Load Action

Retrieves a project/repository specific credential from a 1Password vault.

## credential-load-action

This action automates the process of loading credentials from 1Password vaults
based on project-specific mappings. It checks out Gerrit project code, looks up
the appropriate vault using a JSON mapping, and loads secrets from 1Password.

## Usage Example

<!-- markdownlint-disable MD046 -->

```yaml
steps:
  - name: "Load project credentials"
    id: credential-load
    uses: lfreleng-actions/credential-load-action@main
    with:
      vault_mapping_json: ${{ secrets.VAULT_MAPPING_JSON }}
      op_service_account_token: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
```

<!-- markdownlint-enable MD046 -->

## Inputs

<!-- markdownlint-disable MD013 -->

| Name                     | Required | Default            | Description                              |
| ------------------------ | -------- | ------------------ | ---------------------------------------- |
| op_service_account_token | True     | VAULT_MAPPING_JSON | JSON mapping project to vault            |
| vault_mapping_json       | False    | VAULT_MAPPING_JSON | JSON mapping project to vault            |
| credential               | False    | See note below     | Path to 1Password credential to retrieve |

<!-- markdownlint-enable MD013 -->

### Default Credential Path

If the credential input is not explicitly provided, the action will attempt to
load a credential by performing some logical steps to derive the credential
path.

First, the action calls another action:

```yaml
  - name: "Get 1Password vault from JSON lookup table"
    uses: lfreleng-actions/json-key-value-lookup-action@v0.1.0
    id: vault_lookup
    with:
      json: ${{ inputs.vault_mapping_json }}
      key: ${{ github.repository_owner }}
      exit_on_failure: 'true'
```

This requires JSON, typically provided from a GitHub secret. The JSON maps a
given GitHub organisation to a 1Password vault.

Here is an example:

```json
[
  {"key": "project", "value": "egyqjgwp6qqavqvgodjbiiaqd4" },
  { "key": "second_project", "value": "44bxjvtzkole2oinpahk9km2hy" },
  { "key": "third_project", "value": "9m2ub1pxfbtiniieuxncabx9we" }
]
```

If the github.repository_owner (the GitHub organisation) is "project", then
the vault to query will be "egyqjgwp6qqavqvgodjbiiaqd4".

This is then combined with the repository name to form the full path to the
password item:

```text
op://${{ steps.vault_lookup.outputs.value }}/${{ github.event.repository.name }}/password
```

The action exports CREDENTIAL as an environment variable for use in later
steps. You can make the credential available to later steps by explicitly
passing it into the next step using the variable name the next step expects.

Example:

<!-- markdownlint-disable MD013 -->

```yaml
  - name: Run Maven
    uses: lfreleng-actions/maven-make-build-action@v0.1.0
    env:
      NEXUS_PASSWORD: ${{ env.CREDENTIAL }}
```

<!-- markdownlint-enable MD013 -->

## Outputs

This action does not produce direct outputs, but it loads credentials into the
environment as `CREDENTIAL` which later steps can access.

## Implementation Details

<!-- markdownlint-disable MD013 -->

1. **Checkout**: Uses a Gerrit checkout or GitHub checkout, depending on the workflow trigger/event
2. **Vault Lookup**: Uses organization name as a key to look up the vault from the JSON mapping
3. **Credential Loading**: Loads the credential from 1Password using the vault and repository name
4. **Verification**: Generates and displays a SHA1 sum of the loaded credential for verification

## Notes

- The action loads credentials using the pattern: `op://{vault}/{repository-name}/password`
- The vault mapping JSON should map organization names to their corresponding 1Password vaults
- The loaded credential is available as the `CREDENTIAL` environment variable in later steps
