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

By default, the action derives the credential path from trusted GitHub
context (the repository owner selects the vault, the repository name selects
the item). The optional
`credential_name` input can select a differently named item within that same
vault when the stored credential name differs from the repository name (for
example Gerrit-mirrored repositories). Overrides naming anything other than
the repository's own name require a matching grant in the
administrator-controlled allowlist (see
[Override Grants](#override-grants)). The vault always comes from the owner
mapping, so a repository cannot reach a vault belonging to another project
that shares the same service account.

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

| Name                     | Required | Default | Description                                                                                                                         |
| ------------------------ | -------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| op_service_account_token | True     | n/a     | 1Password service account token                                                                                                     |
| vault_mapping_json       | True     | n/a     | JSON mapping repository owner to 1Password vault; base64 encoded (preferred) or plain JSON                                          |
| credential_name          | False    | ''      | Explicit 1Password item name; overrides the derived repository name (grant required when it differs from the repository's own name) |
| credential_grants_json   | False    | ''      | JSON array of item names this repository may load via `credential_name`; wire from the `CREDENTIAL_LOAD_GRANTS` repository variable |
| export_env               | False    | false   | Export credential as the `CREDENTIAL` environment variable for all later steps                                                      |

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

The action derives the vault from trusted GitHub context (the repository
owner); the calling workflow cannot override the vault selection.

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

### Vault Mapping Encoding

Store the vault mapping secret base64 encoded. Raw JSON in GitHub secrets
degrades workflow log redaction: JSON structural characters, such as
braces and brackets, cause the masking engine to mis-fire, which renders
console logs illegible. Encode the mapping like this:

```shell
base64 -w0 < vault_mapping.json
```

Store the resulting single-line string as the secret value. The action
accepts either form transparently: it first attempts a base64 decode
and, when that does not produce valid JSON, validates the secret content
directly as plain JSON. Plain JSON secrets keep working, and emit a
`notice` annotation recommending migration to base64. This fallback
provides a non-disruptive migration path: upgrade calling workflows to a
release of this action that contains this feature, then re-encode the
secrets without breakage.

Regardless of the input encoding, the action masks each vault identifier
in the mapping (via `::add-mask::`) so vault identifiers never appear in
workflow logs.

This is then combined with the credential item name to form the full path to
the password item:

```text
op://${{ steps.vault_lookup.outputs.value }}/<item-name>/password
```

The action resolves the item name as follows:

1. When the calling workflow sets the `credential_name` input:
   - a value equal to the repository's own derived name loads without
     further checks (it matches the default derivation)
   - any other value requires a matching grant in
     `credential_grants_json` (see [Override Grants](#override-grants));
     without one, the action fails
2. Otherwise, the action uses the repository's own derived name:
   `github.event.repository.name` when present (absent for some
   triggers, such as `workflow_call`), falling back to the repository
   name from the built-in `GITHUB_REPOSITORY` (`owner/repo`), which
   GitHub populates for every event

The explicit `credential_name` override supports Gerrit-mirrored
repositories, where the stored credential name can differ from the mirror
repository name (for example, Gerrit project `sdc/onap-ui-common` maps to
credential name `sdc-onap-ui-common`).

The action validates both the vault identifier and the resolved item name
against a strict character set before use, preventing manipulation of the
`op://` path structure. Each value must match `[A-Za-z0-9._-]+` (ASCII
letters, digits, dot, underscore, and hyphen); any other character, including
whitespace or an embedded newline, causes the action to fail.

### Override Grants

Loading a credential item other than the repository's own name requires an
explicit grant. Grants are a JSON array of permitted item names, supplied
via the `credential_grants_json` input. The canonical wiring sources the
grants from a repository variable with the fixed name
`CREDENTIAL_LOAD_GRANTS`:

```yaml
  - name: "Load project credentials"
    id: credential-load
    uses: lfreleng-actions/credential-load-action@main
    with:
      vault_mapping_json: ${{ secrets.VAULT_MAPPING_JSON }}
      op_service_account_token: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
      credential_name: 'sdc-onap-ui-common'
      credential_grants_json: ${{ vars.CREDENTIAL_LOAD_GRANTS }}
```

With the repository variable set to, for example:

```json
["sdc-onap-ui-common"]
```

This design leverages the Linux Foundation operational model: project teams
do not hold repository administration rights, so repository variables are an
administrator-controlled channel. The Release Engineering team grants access
to extra credential items per repository, on demand, through the GitHub
portal. Reusable workflows in this organisation wire `credential_grants_json`
from `vars.CREDENTIAL_LOAD_GRANTS` internally and do not expose it as a
caller-facing input.

Every active override emits a `notice` annotation in the run log and a line
in the step summary, providing an audit trail.

Note the residual trust boundary: the 1Password service account token grants
vault-wide read access, so code that holds the token can read any item in
the vault without this action. The grants mechanism provides guardrails and
auditability within the maintained actions estate, but cannot substitute
for token scoping. For release jobs, prefer binding
`OP_SERVICE_ACCOUNT_TOKEN` to a protected GitHub environment (with branch
restrictions and/or required reviewers) to gate token access itself.

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
3. **Mapping Normalisation**: Decodes the vault mapping from base64 (falling back to plain JSON), validates it, and masks each vault identifier
4. **Vault Lookup**: Uses the repository owner as a key to look up the vault from the JSON mapping
5. **Path Derivation**: Builds and validates a repository-scoped `op://` path from trusted GitHub context, with `credential_name` as an optional item-name override (grant-gated when it names a different item) and `GITHUB_REPOSITORY` as a fallback when `github.event.repository.name` is absent
6. **Credential Loading**: Loads the credential from 1Password using the derived vault and item name

## Notes

- The action loads credentials using the pattern: `op://{vault}/{item-name}/password`, where the item name defaults to the repository name
- The vault mapping JSON should map repository owner names to their corresponding 1Password vaults; store it base64 encoded to preserve log redaction
- By default the action exposes the credential via the `credential` output; set `export_env: 'true'` to use the `CREDENTIAL` environment variable instead
