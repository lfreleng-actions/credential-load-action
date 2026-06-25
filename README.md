<!--
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# 🔐 Credential Load Action

Retrieves a project/repository specific credential from a 1Password vault.

## credential-load-action

This action automates the process of loading credentials from 1Password vaults
based on project-specific mappings. It looks up the appropriate vault using a
JSON mapping keyed on the calling repository's owner, then loads the credential
belonging to the calling repository from 1Password.

The action derives the credential path solely from trusted GitHub context (the
repository owner selects the vault, the repository name selects the item). A
calling workflow cannot request an arbitrary credential, so a repository loads
its own project's credential and never one belonging to another project that
shares the same service account.

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

| Name                     | Required | Default | Description                                                                    |
| ------------------------ | -------- | ------- | ------------------------------------------------------------------------------ |
| op_service_account_token | True     | n/a     | 1Password service account token                                                |
| vault_mapping_json       | True     | n/a     | JSON mapping repository owner to 1Password vault                               |
| export_env               | False    | false   | Export credential as the `CREDENTIAL` environment variable for all later steps |

<!-- markdownlint-enable MD013 -->

### Trigger Restrictions

The action refuses to run and exits with an error in trigger contexts where
untrusted fork code could execute with secret access:

- The `pull_request_target` event, which runs in the base repository's
  privileged context (with secret access) while operating on fork-controlled
  code.
- Any pull request whose head branch originates from a fork
  (`github.event.pull_request.head.repo.fork == true`).

Load credentials from a trusted trigger such as `push`, `workflow_dispatch`,
or a Gerrit-replicated event instead.

### Credential Path Derivation

The action always derives the credential path from trusted GitHub context; it
cannot be overridden by the calling workflow.

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
given repository owner to a 1Password vault.

Here is an example:

```json
[
  {"key": "project", "value": "egyqjgwp6qqavqvgodjbiiaqd4" },
  { "key": "second_project", "value": "44bxjvtzkole2oinpahk9km2hy" },
  { "key": "third_project", "value": "9m2ub1pxfbtiniieuxncabx9we" }
]
```

If the github.repository_owner (the repository owner) is "project", then
the vault to query will be "egyqjgwp6qqavqvgodjbiiaqd4".

This is then combined with the repository name to form the full path to the
password item:

```text
op://${{ steps.vault_lookup.outputs.value }}/${{ github.event.repository.name }}/password
```

The action validates both the vault identifier and repository name against a
strict character set before use, preventing manipulation of the `op://` path
structure. Each value must match `[A-Za-z0-9._-]+` (ASCII letters, digits,
dot, underscore, and hyphen); any other character, including whitespace or an
embedded newline, causes the action to fail.

### Consuming the Credential

By default (`export_env: 'false'`) the action does **not** write the credential
to the job environment. Instead it sets the `credential` output, scoping access
to steps that explicitly reference it.

<!-- markdownlint-disable MD013 -->

```yaml
  - name: "Load project credentials"
    id: credential-load
    uses: lfreleng-actions/credential-load-action@main
    with:
      vault_mapping_json: ${{ secrets.VAULT_MAPPING_JSON }}
      op_service_account_token: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}

  - name: Run Maven
    uses: lfreleng-actions/maven-make-build-action@v0.1.0
    env:
      NEXUS_PASSWORD: ${{ steps.credential-load.outputs.credential }}
```

<!-- markdownlint-enable MD013 -->

Set `export_env: 'true'` when you need the credential available to every later
step in the job as the `CREDENTIAL` environment variable. This broadens
exposure, so prefer the output where practical.

<!-- markdownlint-disable MD013 -->

```yaml
  - name: "Load project credentials"
    uses: lfreleng-actions/credential-load-action@main
    with:
      vault_mapping_json: ${{ secrets.VAULT_MAPPING_JSON }}
      op_service_account_token: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
      export_env: 'true'

  - name: Run Maven
    uses: lfreleng-actions/maven-make-build-action@v0.1.0
    env:
      NEXUS_PASSWORD: ${{ env.CREDENTIAL }}
```

<!-- markdownlint-enable MD013 -->

## Outputs

<!-- markdownlint-disable MD013 -->

| Name       | Description                                                   |
| ---------- | ------------------------------------------------------------- |
| credential | The loaded credential, populated when `export_env` is `false` |

<!-- markdownlint-enable MD013 -->

When `export_env` is `true`, the credential is instead exported into the job
environment as `CREDENTIAL` and the `credential` output is empty.

## Implementation Details

<!-- markdownlint-disable MD013 -->

1. **Trigger Guard**: Refuses to run on `pull_request_target` or fork pull requests before using the service account token
2. **Checkout**: Checks out the repository with `persist-credentials: false`
3. **Vault Lookup**: Uses the repository owner as a key to look up the vault from the JSON mapping
4. **Path Derivation**: Builds and validates a repository-scoped `op://` path from trusted GitHub context
5. **Credential Loading**: Loads the credential from 1Password using the derived vault and repository name

## Notes

- The action loads credentials using the pattern: `op://{vault}/{repository-name}/password`
- The vault mapping JSON should map repository owner names to their corresponding 1Password vaults
- By default the action exposes the credential via the `credential` output; set `export_env: 'true'` to use the `CREDENTIAL` environment variable instead
