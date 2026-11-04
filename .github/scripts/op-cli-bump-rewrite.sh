#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Plan the 1Password CLI bump for one copy of action.yaml.
#
# Usage: bash op-cli-bump-rewrite.sh <source> <destination> <latest>
#
# Reads the op CLI version pinned in <source> (the single-quoted
# `version: 'X.Y.Z'` input passed to 1password/load-secrets-action).
# When <latest> sorts above it, writes <source> to <destination> with
# that one line set to <latest>, keeping its indentation and quoting.
# Prints key=value lines on stdout: pinned, outdated and, when
# outdated, title, old_line and new_line.
#
# Exits 0 on success, 1 when <latest> is not X.Y.Z, when <source> does
# not pin exactly one version, or when the rewrite does not change
# exactly one line, and 2 on a usage error.

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo 'Usage: bash op-cli-bump-rewrite.sh <source> <destination> <latest>' >&2
  exit 2
fi

src="$1"
dst="$2"
latest="$3"
version_re='[0-9]+\.[0-9]+\.[0-9]+'
line_re="^[[:space:]]*version: '${version_re}'[[:space:]]*\$"
max_title=50

fail() {
  echo "::error::$1" >&2
  exit 1
}

if ! [[ "${latest}" =~ ^${version_re}$ ]]; then
  fail "Latest op CLI version '${latest}' is not X.Y.Z"
fi

count="$(grep -cE "${line_re}" "${src}" || true)"
if [ "${count}" != '1' ]; then
  fail "Expected one pinned op CLI version in ${src}, found ${count}"
fi
old_line="$(grep -E "${line_re}" "${src}")"
pinned="$(printf '%s\n' "${old_line}" | grep -oE "${version_re}")"
echo "pinned=${pinned}"

highest="$(printf '%s\n%s\n' "${pinned}" "${latest}" | sort -V | tail -n1)"
if [ "${pinned}" = "${latest}" ] || [ "${highest}" != "${latest}" ]; then
  echo 'outdated=false'
  exit 0
fi

prefix="^([[:space:]]*version: ')"
suffix="('[[:space:]]*)\$"
sed -E "s/${prefix}${version_re}${suffix}/\1${latest}\2/" "${src}" > "${dst}"
removed="$(diff "${src}" "${dst}" | grep -c '^<' || true)"
added="$(diff "${src}" "${dst}" | grep -c '^>' || true)"
if [ "${removed}" != '1' ] || [ "${added}" != '1' ]; then
  fail "Rewrite removed ${removed} line(s), added ${added}; expected one each"
fi
new_line="$(grep -E "${line_re}" "${dst}")"

title="Chore: Bump 1Password CLI from ${pinned} to ${latest}"
if [ "${#title}" -gt "${max_title}" ]; then
  title="Chore: Bump 1Password CLI to ${latest}"
fi

echo 'outdated=true'
echo "title=${title}"
echo "old_line=${old_line}"
echo "new_line=${new_line}"
