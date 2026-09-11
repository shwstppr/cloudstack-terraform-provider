#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# Functional test runner.
#
# Builds the terraform-provider-cloudstack binary from a specific git SHA or
# tag (in an isolated git worktree, so your current checkout is left alone),
# installs it as a Terraform local provider, then runs each test case under
# ./cases/ (init -> validate -> apply -> drift-check plan -> destroy) against
# a real CloudStack environment described by a caller-supplied tfvars file.
#
# Usage:
#   ./scripts/terraform-tests/run-acs-terraform-tests.sh --ref <sha-or-tag> --tfvars <path> [options]
#
# Required:
#   --ref <sha-or-tag>   Git commit SHA or tag to build the provider from.
#                         Not required with --generate-only (see below).
#   --tfvars <path>      Path to a terraform.tfvars file with connection details
#                         and environment IDs. See common/terraform.tfvars.example.
#                         Defaults to common/terraform.tfvars.example when used
#                         with --generate-only.
#
# Options:
#   --generate-only      Only render each case's .tf/.tfvars files into the run
#                         directory and print their paths - skip building/installing
#                         the provider and skip running terraform entirely. Useful
#                         for reviewing or hand-editing the generated configs before
#                         actually applying them against a real environment. Implies
#                         --keep-workdir. --ref is optional in this mode (used only
#                         to label the provider version placeholder in versions.tf).
#   --remote <name>      Git remote to fetch the ref from if not found locally (default: origin)
#   --only <patterns>    Comma-separated glob(s) matched against case directory names,
#                         e.g. --only '01-*,05-*' to run a subset.
#   --keep-resources     Skip 'terraform destroy' after each case (for debugging).
#   --keep-workdir       Keep the worktree + per-case run directories instead of cleaning up.
#   --workdir <dir>      Use this directory instead of a freshly created temp dir.
#   -h, --help           Show this help
#
# Example:
#   ./scripts/terraform-tests/run-acs-terraform-tests.sh \
#     --ref v0.7.0-rc2 \
#     --tfvars ~/cloudstack-test.tfvars \
#     --only '01-*,02-*,03-*'
#
#   # Just generate the .tf files for review, without building or running anything:
#   ./scripts/terraform-tests/run-acs-terraform-tests.sh --generate-only --only '02-*'

set -uo pipefail

REF=""
TFVARS=""
REMOTE="origin"
ONLY=""
KEEP_RESOURCES=0
KEEP_WORKDIR=0
WORKDIR=""
GENERATE_ONLY=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CASES_DIR="$SCRIPT_DIR/cases"
COMMON_DIR="$SCRIPT_DIR/common"

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --ref) REF="$2"; shift 2 ;;
        --tfvars) TFVARS="$2"; shift 2 ;;
        --remote) REMOTE="$2"; shift 2 ;;
        --only) ONLY="$2"; shift 2 ;;
        --keep-resources) KEEP_RESOURCES=1; shift ;;
        --keep-workdir) KEEP_WORKDIR=1; shift ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        --generate-only) GENERATE_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 2 ;;
        *) echo "Unexpected argument: $1" >&2; usage; exit 2 ;;
    esac
done

if [ -z "$REF" ] && [ "$GENERATE_ONLY" -eq 0 ]; then
    echo "Error: --ref <sha-or-tag> is required (unless --generate-only is set)." >&2
    usage; exit 2
fi
if [ -z "$TFVARS" ]; then
    if [ "$GENERATE_ONLY" -eq 1 ]; then
        TFVARS="$COMMON_DIR/terraform.tfvars.example"
    else
        echo "Error: --tfvars <path> is required." >&2
        usage; exit 2
    fi
fi
if [ ! -f "$TFVARS" ]; then
    echo "Error: tfvars file not found: $TFVARS" >&2
    exit 2
fi
TFVARS="$(cd "$(dirname "$TFVARS")" && pwd)/$(basename "$TFVARS")"

if [ "$GENERATE_ONLY" -eq 1 ]; then
    KEEP_WORKDIR=1
fi

REQUIRED_BINS=()
if [ "$GENERATE_ONLY" -eq 0 ]; then
    REQUIRED_BINS+=(git go terraform)
elif [ -n "$REF" ]; then
    REQUIRED_BINS+=(git)
fi
for bin in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "Error: required tool '$bin' not found in PATH." >&2
        exit 3
    fi
done

CLEANUP_WORKDIR=0
if [ -z "$WORKDIR" ]; then
    WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/terraform-tests.XXXXXX")"
    CLEANUP_WORKDIR=1
else
    mkdir -p "$WORKDIR"
fi
SRC_DIR="$WORKDIR/src"
RUN_DIR="$WORKDIR/run"
mkdir -p "$RUN_DIR"

cleanup() {
    if git -C "$REPO_ROOT" worktree list 2>/dev/null | grep -q "$SRC_DIR"; then
        git -C "$REPO_ROOT" worktree remove --force "$SRC_DIR" >/dev/null 2>&1 || true
    fi
    if [ "$KEEP_WORKDIR" -eq 0 ] && [ "$CLEANUP_WORKDIR" -eq 1 ]; then
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT

echo "==> Repo:       $REPO_ROOT"
echo "==> Ref:        $REF"
echo "==> tfvars:     $TFVARS"
echo "==> Workdir:    $WORKDIR"
echo

# --- Resolve the ref, fetching from $REMOTE if necessary -------------------
PROVIDER_VERSION="0.0.0-dev"
if [ -n "$REF" ]; then
    echo "--> Fetching tags/refs from '$REMOTE'..."
    git -C "$REPO_ROOT" fetch "$REMOTE" --tags --quiet || true

    RESOLVED_SHA=""
    if git -C "$REPO_ROOT" rev-parse --verify --quiet "${REF}^{commit}" >/dev/null; then
        RESOLVED_SHA="$(git -C "$REPO_ROOT" rev-parse "${REF}^{commit}")"
    else
        echo "--> Ref not found locally, fetching '$REF' from '$REMOTE'..."
        if git -C "$REPO_ROOT" fetch "$REMOTE" "$REF" --quiet; then
            RESOLVED_SHA="$(git -C "$REPO_ROOT" rev-parse FETCH_HEAD)"
        else
            echo "Error: could not resolve ref '$REF' locally or via 'git fetch $REMOTE $REF'." >&2
            exit 1
        fi
    fi
    SHORT_SHA="$(git -C "$REPO_ROOT" rev-parse --short "$RESOLVED_SHA")"
    echo "    Resolved to commit: $RESOLVED_SHA"

    # Derive a Terraform-compatible version string: strip a leading 'v' from a
    # tag-like ref so it's a plain semver (e.g. v0.7.0-rc2 -> 0.7.0-rc2);
    # otherwise synthesize one from the short SHA.
    if [[ "$REF" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?)$ ]]; then
        PROVIDER_VERSION="${BASH_REMATCH[1]}"
    else
        PROVIDER_VERSION="0.0.0-${SHORT_SHA}"
    fi
fi
echo "    Provider version for this run: $PROVIDER_VERSION"

# --- Isolated worktree + build ----------------------------------------------
if [ "$GENERATE_ONLY" -eq 1 ]; then
    echo "--> --generate-only set: skipping worktree checkout, build, install, and terraform execution."
else
    echo "--> Creating worktree at $SRC_DIR..."
    if ! git -C "$REPO_ROOT" worktree add --detach --force "$SRC_DIR" "$RESOLVED_SHA" >"$WORKDIR/worktree-add.log" 2>&1; then
        cat "$WORKDIR/worktree-add.log" >&2
        echo "Error: could not create git worktree for $RESOLVED_SHA" >&2
        exit 1
    fi

    echo "--> Building provider binary..."
    if ! (cd "$SRC_DIR" && go build -o "$WORKDIR/terraform-provider-cloudstack" .) >"$WORKDIR/build.log" 2>&1; then
        cat "$WORKDIR/build.log" >&2
        echo "Error: build failed for ref $REF ($RESOLVED_SHA)" >&2
        exit 1
    fi

    OS_ARCH="$(go env GOOS)_$(go env GOARCH)"
    PLUGIN_DIR="$HOME/.terraform.d/plugins/local/cloudstack/cloudstack/${PROVIDER_VERSION}/${OS_ARCH}"
    mkdir -p "$PLUGIN_DIR"
    cp "$WORKDIR/terraform-provider-cloudstack" "$PLUGIN_DIR/terraform-provider-cloudstack_v${PROVIDER_VERSION}"
    chmod +x "$PLUGIN_DIR/terraform-provider-cloudstack_v${PROVIDER_VERSION}"
    echo "    Installed to: $PLUGIN_DIR"
fi
echo

# --- Select cases ------------------------------------------------------------
mapfile -t ALL_CASES < <(find "$CASES_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
if [ "${#ALL_CASES[@]}" -eq 0 ]; then
    echo "Error: no test cases found under $CASES_DIR" >&2
    exit 1
fi

CASES=()
if [ -z "$ONLY" ]; then
    CASES=("${ALL_CASES[@]}")
else
    IFS=',' read -ra PATTERNS <<< "$ONLY"
    for c in "${ALL_CASES[@]}"; do
        for p in "${PATTERNS[@]}"; do
            # shellcheck disable=SC2053
            if [[ "$c" == $p ]]; then
                CASES+=("$c")
                break
            fi
        done
    done
fi

if [ "${#CASES[@]}" -eq 0 ]; then
    echo "Error: --only '$ONLY' matched no cases (available: ${ALL_CASES[*]})" >&2
    exit 1
fi

stage_case() {
    local case_name="$1"
    local case_src="$CASES_DIR/$case_name"
    local case_run="$RUN_DIR/$case_name"
    mkdir -p "$case_run"

    cp "$COMMON_DIR/variables.tf" "$case_run/variables.tf"
    sed "s/__PROVIDER_VERSION__/${PROVIDER_VERSION}/" "$COMMON_DIR/versions.tf.tmpl" > "$case_run/versions.tf"
    cp "$case_src/main.tf" "$case_run/main.tf"
    cp "$TFVARS" "$case_run/terraform.tfvars"
}

if [ "$GENERATE_ONLY" -eq 1 ]; then
    echo "==> Generating Terraform files for ${#CASES[@]} case(s): ${CASES[*]}"
    echo
    for c in "${CASES[@]}"; do
        stage_case "$c"
        echo "Generated: $RUN_DIR/$c/  (versions.tf, variables.tf, main.tf, terraform.tfvars)"
    done
    echo
    echo "Review/edit the files above, then run e.g.:"
    echo "  terraform -chdir=$RUN_DIR/<case> init"
    echo "  terraform -chdir=$RUN_DIR/<case> apply"
    echo
    echo "RESULT: GENERATED"
    exit 0
fi

echo "==> Running ${#CASES[@]} case(s): ${CASES[*]}"
echo

declare -A CASE_RESULT
OVERALL_FAILED=0

run_case() {
    local case_name="$1"
    local case_run="$RUN_DIR/$case_name"
    stage_case "$case_name"

    echo "===================================================="
    echo "Case: $case_name"
    echo "===================================================="

    local -A stage
    local tf="terraform -chdir=$case_run"

    if $tf init -no-color -input=false >"$case_run/init.log" 2>&1; then stage[init]=PASS; else stage[init]=FAIL; fi
    echo "    init:     ${stage[init]}"

    if [ "${stage[init]}" = PASS ]; then
        if $tf validate -no-color >"$case_run/validate.log" 2>&1; then stage[validate]=PASS; else stage[validate]=FAIL; fi
    else
        stage[validate]=SKIP
    fi
    echo "    validate: ${stage[validate]}"

    if [ "${stage[validate]}" = PASS ]; then
        if $tf apply -no-color -auto-approve -input=false >"$case_run/apply.log" 2>&1; then stage[apply]=PASS; else stage[apply]=FAIL; fi
    else
        stage[apply]=SKIP
    fi
    echo "    apply:    ${stage[apply]}"

    if [ "${stage[apply]}" = PASS ]; then
        # detailed-exitcode: 0 = no changes, 2 = drift detected, 1 = error
        $tf plan -no-color -detailed-exitcode -input=false >"$case_run/drift-plan.log" 2>&1
        local rc=$?
        if [ "$rc" -eq 0 ]; then stage[drift]=PASS; elif [ "$rc" -eq 2 ]; then stage[drift]=FAIL; else stage[drift]=FAIL; fi
    else
        stage[drift]=SKIP
    fi
    echo "    no-drift: ${stage[drift]}"

    # Optional second phase: if the case ships a main.tf.update, apply it on
    # top of the already-applied config and check for a clean follow-up plan.
    # This is how in-place Update behavior (as opposed to create/destroy) gets
    # exercised, since a single apply can't test a config change.
    if [ -f "$CASES_DIR/$case_name/main.tf.update" ]; then
        if [ "${stage[drift]}" = PASS ]; then
            cp "$CASES_DIR/$case_name/main.tf.update" "$case_run/main.tf"
            if $tf apply -no-color -auto-approve -input=false >"$case_run/update-apply.log" 2>&1; then stage[update_apply]=PASS; else stage[update_apply]=FAIL; fi
        else
            stage[update_apply]=SKIP
        fi
        echo "    update:   ${stage[update_apply]}"

        if [ "${stage[update_apply]}" = PASS ]; then
            $tf plan -no-color -detailed-exitcode -input=false >"$case_run/update-drift-plan.log" 2>&1
            local update_rc=$?
            if [ "$update_rc" -eq 0 ]; then stage[update_drift]=PASS; else stage[update_drift]=FAIL; fi
        else
            stage[update_drift]=SKIP
        fi
        echo "    update-no-drift: ${stage[update_drift]}"
    else
        stage[update_apply]=NA
        stage[update_drift]=NA
    fi

    if [ "$KEEP_RESOURCES" -eq 0 ] && [ "${stage[apply]}" = PASS ]; then
        if $tf destroy -no-color -auto-approve -input=false >"$case_run/destroy.log" 2>&1; then stage[destroy]=PASS; else stage[destroy]=FAIL; fi
    elif [ "$KEEP_RESOURCES" -eq 1 ]; then
        stage[destroy]=SKIPPED_BY_FLAG
    else
        stage[destroy]=SKIP
    fi
    echo "    destroy:  ${stage[destroy]}"

    local overall=PASS
    for s in init validate apply drift; do
        if [ "${stage[$s]}" != PASS ]; then overall=FAIL; fi
    done
    if [ "${stage[update_apply]}" != PASS ] && [ "${stage[update_apply]}" != NA ]; then overall=FAIL; fi
    if [ "${stage[update_drift]}" != PASS ] && [ "${stage[update_drift]}" != NA ]; then overall=FAIL; fi
    if [ "${stage[destroy]}" = FAIL ]; then overall=FAIL; fi

    local update_summary=""
    if [ "${stage[update_apply]}" != NA ]; then
        update_summary=" update=${stage[update_apply]} update_drift=${stage[update_drift]}"
    fi

    CASE_RESULT["$case_name"]="$overall (init=${stage[init]} validate=${stage[validate]} apply=${stage[apply]} drift=${stage[drift]}${update_summary} destroy=${stage[destroy]})"
    echo "    logs:     $case_run/{init,validate,apply,drift-plan,destroy}.log"
    echo

    [ "$overall" = PASS ]
}

for c in "${CASES[@]}"; do
    if ! run_case "$c"; then
        OVERALL_FAILED=1
    fi
done

echo "===================== Summary ====================="
for c in "${CASES[@]}"; do
    printf "%-30s %s\n" "$c" "${CASE_RESULT[$c]}"
done
echo "====================================================="

if [ "$KEEP_WORKDIR" -eq 1 ] || [ "$KEEP_RESOURCES" -eq 1 ]; then
    echo "Run directories kept at: $RUN_DIR"
fi

if [ "$OVERALL_FAILED" -ne 0 ]; then
    echo "RESULT: FAIL"
    exit 1
fi

echo "RESULT: PASS"
exit 0
