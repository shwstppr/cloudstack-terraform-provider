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
# Generates a terraform.tfvars file (see common/variables.tf) for a
# CloudStack environment, given its API URL and an admin username/password.
# Talks to CloudStack via the `cmk` (CloudMonkey) CLI rather than calling the
# API directly.
#
# It logs in with the given credentials, creates (or reuses) a dedicated
# API-only account so it never touches/invalidates the caller's own API key,
# registers a key pair for it, then queries the environment for a zone,
# template, network offering and VPC offering to fill in the rest of the
# tfvars file. Values can be overridden with the options below when the
# environment has more than one candidate and the auto-picked one isn't
# the one you want.
#
# cmk profile handling: username/password login is only needed to bootstrap
# the dedicated account, and cmk only authenticates via a *profile* (not
# with -u/-k/-s, which are apikey/secretkey-only). So this script points a
# single named profile (--cmk-profile, default "tf-profile") at the given
# env for that bootstrap step only - creating the profile if it doesn't
# already exist - and switches cmk's active profile back to whatever it was
# before once done. Every call after that (the zone/template/offering
# discovery, which only needs read access) uses the freshly-registered
# apikey/secretkey directly via `cmk -u -k -s`, without touching any profile.
#
# Usage:
#   ./scripts/terraform-tests/generate-tfvars.sh \
#     --api-url <url> --username <user> --password <pass> --out <path> [options]
#
# Required:
#   --api-url <url>       CloudStack API endpoint, e.g. http://host:8080/client/api
#   --username <user>     Login username (needs enough privilege to create an account)
#   --password <pass>     Login password
#   --out <path>          Where to write the generated tfvars file
#
# Options:
#   --domain <path>              Login domain path (default: /)
#   --account <name>             Name of the dedicated account to create/reuse for
#                                 API keys (default: tf-test). Created as Root Admin
#                                 if it doesn't already exist.
#   --cmk-profile <name>          cmk profile to use for the bootstrap login step
#                                 (default: tf-profile). Created if it doesn't
#                                 already exist; cmk's active profile is restored
#                                 to whatever it was before this script ran.
#   --zone <name>                Zone name to use (default: first Enabled zone)
#   --network-offering <name>    Network offering name (default: prefers
#                                 DefaultIsolatedNetworkOfferingWithSourceNatService,
#                                 else the first Enabled non-VPC offering)
#   --vpc-offering <name>        VPC offering name (default: prefers "Default VPC
#                                 offering", else the first Enabled one)
#   --template-name <name>       Template name to match exactly (default: first
#                                 template returned by templatefilter=executable)
#   --kubernetes-version <name>  Kubernetes ISO/version name, for the optional
#                                 kubernetes-cluster case (default: empty)
#   -h, --help                   Show this help
#
# Example:
#   ./scripts/terraform-tests/generate-tfvars.sh \
#     --api-url http://172.120.0.135:8080/client/api \
#     --username admin --password password \
#     --out ~/cloudstack-test.tfvars

set -uo pipefail

API_URL=""
USERNAME=""
PASSWORD=""
OUT=""
DOMAIN="/"
ACCOUNT="tf-test"
CMK_PROFILE="tf-profile"
ZONE_NAME=""
NETWORK_OFFERING_NAME=""
VPC_OFFERING_NAME=""
TEMPLATE_NAME=""
KUBERNETES_VERSION=""

usage() {
    sed -n '2,63p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --api-url) API_URL="$2"; shift 2 ;;
        --username) USERNAME="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --account) ACCOUNT="$2"; shift 2 ;;
        --cmk-profile) CMK_PROFILE="$2"; shift 2 ;;
        --zone) ZONE_NAME="$2"; shift 2 ;;
        --network-offering) NETWORK_OFFERING_NAME="$2"; shift 2 ;;
        --vpc-offering) VPC_OFFERING_NAME="$2"; shift 2 ;;
        --template-name) TEMPLATE_NAME="$2"; shift 2 ;;
        --kubernetes-version) KUBERNETES_VERSION="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 2 ;;
        *) echo "Unexpected argument: $1" >&2; usage; exit 2 ;;
    esac
done

for req in API_URL USERNAME PASSWORD OUT; do
    if [ -z "${!req}" ]; then
        echo "Error: --$(echo "$req" | tr '[:upper:]' '[:lower:]' | tr '_' '-') is required." >&2
        usage; exit 2
    fi
done

for bin in cmk python3; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "Error: required tool '$bin' not found in PATH." >&2
        exit 3
    fi
done

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/gen-tfvars.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

# jf <file> <python-statement(s)-on-`d`, must print its own result>
jf() {
    python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
$2
" "$1"
}

# --- Bootstrap the dedicated account via a cmk profile ----------------------
# cmk only supports username/password auth through a stored profile, so this
# is the one part of the script that has to touch cmk's config. The active
# profile is saved and restored so the caller's own default is undisturbed.
ORIGINAL_PROFILE="$(cmk -d version 2>&1 | grep -oP 'profiles/\K[^./]+(?=\.cache)' | head -1)"
restore_profile() {
    if [ -n "$ORIGINAL_PROFILE" ]; then
        cmk set profile "$ORIGINAL_PROFILE" >/dev/null 2>&1 || true
    fi
}
trap 'restore_profile; rm -rf "$WORKDIR"' EXIT

echo "==> Configuring cmk profile '$CMK_PROFILE' for $API_URL..."
cmk set profile "$CMK_PROFILE" >/dev/null
cmk set url "$API_URL" >/dev/null
cmk set username "$USERNAME" >/dev/null
cmk set password "$PASSWORD" >/dev/null
cmk set domain "$DOMAIN" >/dev/null
cmk set output json >/dev/null

# A freshly created/switched-to profile has no API cache yet, and cmk prints
# a "Loaded in-built API cache..." warning on the first call after that -
# sync first so that noise doesn't show up (or get captured) later.
cmk sync >/dev/null 2>&1

echo "--> Resolving/creating dedicated account '$ACCOUNT'..."
# Stdout only goes to the JSON capture file; stderr (errors, warnings) is
# left to print directly rather than being merged in and corrupting the JSON.
cmk list accounts name="$ACCOUNT" listall=true > "$WORKDIR/list-account.json"
ACCOUNT_EXISTS="$(jf "$WORKDIR/list-account.json" "print('true' if d.get('count') else 'false')" 2>/dev/null || echo false)"

if [ "$ACCOUNT_EXISTS" = "true" ]; then
    echo "    Account already exists, reusing it."
    USER_ID="$(jf "$WORKDIR/list-account.json" "print(d['account'][0]['user'][0]['id'])")"
else
    RANDOM_PW="$(python3 -c 'import secrets; print(secrets.token_urlsafe(18))')"
    cmk create account accounttype=1 username="$ACCOUNT" password="$RANDOM_PW" \
        firstname=tf lastname=test email="${ACCOUNT}@example.invalid" account="$ACCOUNT" \
        > "$WORKDIR/create-account.json"
    if ! jf "$WORKDIR/create-account.json" "print(d['account']['id'])" >/dev/null 2>&1; then
        echo "Error: could not create account '$ACCOUNT'. Response:" >&2
        cat "$WORKDIR/create-account.json" >&2
        exit 1
    fi
    USER_ID="$(jf "$WORKDIR/create-account.json" "print(d['account']['user'][0]['id'])")"
    echo "    Created account, user id: $USER_ID"
fi

echo "--> Registering API keys for user $USER_ID..."
cmk register userkeys id="$USER_ID" > "$WORKDIR/regkeys.json"
if ! jf "$WORKDIR/regkeys.json" "print(d['userkeys']['apikey'])" >/dev/null 2>&1; then
    echo "Error: could not register API keys. Response:" >&2
    cat "$WORKDIR/regkeys.json" >&2
    exit 1
fi
API_KEY="$(jf "$WORKDIR/regkeys.json" "print(d['userkeys']['apikey'])")"
SECRET_KEY="$(jf "$WORKDIR/regkeys.json" "print(d['userkeys']['secretkey'])")"
echo "    Got API key/secret."

restore_profile
echo "    Restored cmk's active profile to '${ORIGINAL_PROFILE:-<none>}'."

# --- Environment discovery (apikey/secretkey directly, no profile needed) --
api_call() {
    # api_call <output-file> <cmk-verb-and-args...>
    local out="$1"; shift
    cmk -u "$API_URL" -k "$API_KEY" -s "$SECRET_KEY" -o json "$@" > "$out"
}

echo "--> Discovering zone..."
api_call "$WORKDIR/zones.json" list zones state=Enabled
if [ -n "$ZONE_NAME" ]; then
    ZONE_ID="$(jf "$WORKDIR/zones.json" "print(next(z['id'] for z in d['zone'] if z['name']=='$ZONE_NAME'))")"
else
    ZONE_NAME="$(jf "$WORKDIR/zones.json" "print(d['zone'][0]['name'])")"
    ZONE_ID="$(jf "$WORKDIR/zones.json" "print(d['zone'][0]['id'])")"
fi
echo "    zone = $ZONE_NAME ($ZONE_ID)"

echo "--> Discovering template..."
api_call "$WORKDIR/templates.json" list templates templatefilter=executable zoneid="$ZONE_ID"
if [ -z "$TEMPLATE_NAME" ]; then
    TEMPLATE_NAME="$(jf "$WORKDIR/templates.json" "print(d['template'][0]['name'])")"
fi
echo "    template = $TEMPLATE_NAME"

echo "--> Discovering network offering..."
api_call "$WORKDIR/netofferings.json" list networkofferings state=Enabled
if [ -z "$NETWORK_OFFERING_NAME" ]; then
    NETWORK_OFFERING_NAME="$(jf "$WORKDIR/netofferings.json" "
offs = d['networkoffering']
preferred = next((o['name'] for o in offs if o['name']=='DefaultIsolatedNetworkOfferingWithSourceNatService'), None)
print(preferred or next(o['name'] for o in offs if o.get('forvpc') in (False,'false',None)))
")"
fi
echo "    network_offering = $NETWORK_OFFERING_NAME"

echo "--> Discovering VPC offering..."
api_call "$WORKDIR/vpcofferings.json" list vpcofferings state=Enabled
if [ -z "$VPC_OFFERING_NAME" ]; then
    VPC_OFFERING_NAME="$(jf "$WORKDIR/vpcofferings.json" "
offs = d['vpcoffering']
preferred = next((o['name'] for o in offs if o['name']=='Default VPC offering'), None)
print(preferred or offs[0]['name'])
")"
fi
echo "    vpc_offering = $VPC_OFFERING_NAME"

# --- Write tfvars -------------------------------------------------------------
# hcl_escape: minimal escaping (backslash, double-quote) for embedding a plain
# value inside an HCL double-quoted string literal.
hcl_escape() {
    printf '%s' "$1" | python3 -c "import sys; print(sys.stdin.read().replace(chr(92), chr(92)*2).replace(chr(34), chr(92)+chr(34)), end='')"
}

TEMPLATE_NAME_REGEX="$(python3 - "$TEMPLATE_NAME" <<'PYEOF'
import re, sys
name = sys.argv[1]
# Escape Go-regexp metacharacters only (not spaces - re.escape() escapes
# those too, which then breaks as an HCL string literal).
escaped = re.sub(r'([\\.^$|()\[\]{}*+?])', lambda m: '\\' + m.group(1), name)
pattern = '^' + escaped + '$'
# Double backslashes so the value survives HCL string-literal parsing.
print(pattern.replace('\\', '\\\\'))
PYEOF
)"

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<EOF
cloudstack_api_url    = "$(hcl_escape "$API_URL")"
cloudstack_api_key    = "$(hcl_escape "$API_KEY")"
cloudstack_secret_key = "$(hcl_escape "$SECRET_KEY")"

zone    = "$(hcl_escape "$ZONE_NAME")"
zone_id = "$(hcl_escape "$ZONE_ID")"

network_offering = "$(hcl_escape "$NETWORK_OFFERING_NAME")"
vpc_offering     = "$(hcl_escape "$VPC_OFFERING_NAME")"

template_filter      = "executable"
template_name_regex  = "$TEMPLATE_NAME_REGEX"
template_name        = "$(hcl_escape "$TEMPLATE_NAME")"

kubernetes_version = "$(hcl_escape "$KUBERNETES_VERSION")"
EOF

chmod 600 "$OUT"
echo
echo "Wrote $OUT (mode 600 - contains live API credentials, keep it out of version control)."
