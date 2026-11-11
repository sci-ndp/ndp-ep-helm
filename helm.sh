#!/usr/bin/env bash
# Deploy ndp-ep-helm.
#
# Fetches the federation document before calling helm so that optional
# sub-charts (kafka-kraft, ndp-jupyterhub, rexec) can be enabled/disabled
# based on the federation configuration.

set -euo pipefail

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
CONFIG_ID=""
CLUSTER_HOST=""
CLUSTER_PUBLIC_HOST=""
STORAGE_CLASS=""
INGRESS_CLASS=""
NDP_ENV="prod"
NAMESPACE="ndp-ep"
RELEASE_NAME=""
LOGIN_CLIENT_ID="${NDP_LOGIN_CLIENT_ID:-}"
NDP_TOKEN_FILE=""

# --------------------------------------------------------------------------
# Parse flags
# --------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-id|--config_id)  CONFIG_ID="$2";             shift 2 ;;
    --host)                   CLUSTER_HOST="$2";          shift 2 ;;
    --public-host)            CLUSTER_PUBLIC_HOST="$2";   shift 2 ;;
    --storage-class)          STORAGE_CLASS="$2";         shift 2 ;;
    --ingress-class)          INGRESS_CLASS="$2";         shift 2 ;;
    --env)                    NDP_ENV="$2";               shift 2 ;;
    --namespace)              NAMESPACE="$2";             shift 2 ;;
    --release-name)           RELEASE_NAME="$2";          shift 2 ;;
    --login-client-id)        LOGIN_CLIENT_ID="$2";       shift 2 ;;
    --ndp-token-file)         NDP_TOKEN_FILE="$2";        shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# Default the release name to the namespace so that parallel deployments
# (e.g. a "test" namespace alongside "prod") never share a Helm release
# name. This matters because some sub-charts (rexec-server-deployment-api)
# create cluster-scoped resources (ClusterRole/ClusterRoleBinding) whose
# names are derived from the release name only, not the namespace — two
# releases sharing a name would collide on those cluster-scoped objects.
[[ -z "$RELEASE_NAME" ]] && RELEASE_NAME="$NAMESPACE"

# --------------------------------------------------------------------------
# Validate mandatory flags
# --------------------------------------------------------------------------
MISSING=()
[[ -z "$CONFIG_ID"     ]] && MISSING+=("--config-id")
[[ -z "$CLUSTER_HOST"  ]] && MISSING+=("--host")
[[ -z "$STORAGE_CLASS" ]] && MISSING+=("--storage-class")
[[ -z "$INGRESS_CLASS" ]] && MISSING+=("--ingress-class")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Error: missing required flags: ${MISSING[*]}"
  echo ""
  echo "Usage: $0 --config-id <id> --host <host> --storage-class <class> --ingress-class <class> [--public-host <domain>] [--env test] [--namespace <ns>] [--release-name <name>] [--ndp-token-file <path>] [--login-client-id <id>]"
  exit 1
fi

# --------------------------------------------------------------------------
# Derive federation URL (mirrors _helpers.tpl logic)
# --------------------------------------------------------------------------
if [[ "$NDP_ENV" == "test" ]]; then
  FEDERATION_URL="https://test.federation.ndp.utah.edu"
else
  FEDERATION_URL="https://federation.ndp.utah.edu"
fi

# --------------------------------------------------------------------------
# NDP access token for the Federation (OAuth 2.0 device flow, RFC 8628)
# --------------------------------------------------------------------------
# Federation 2.0.0 answers GET /ep/{config_id} only to an admin of the
# Endpoint, identified by the caller's Bearer token. Older Federations have no
# authentication on that route and ignore the header, so the script always
# gets a token and sends it: from --ndp-token-file for unattended runs, else by
# signing in the person running the script with the device flow:
#
#   1. ask the identity provider for a device code and a short user code
#   2. show a link and the code, to open in a browser on any device
#   3. poll the token endpoint until the person has signed in
#
# Works on headless servers, with nothing to copy or paste. The token and the
# device code never go on a command line (other users could read them with
# `ps`): curl reads them from files in a private directory, removed on exit.

# ---- Identity provider and login client, per --env -----------------------
# The client must be a public client of the realm with "OAuth 2.0 Device
# Authorization Grant" enabled. The production IdP has none yet, so on prod
# there is no sign-in (and the Federation is asked without a token) unless
# --login-client-id (or NDP_LOGIN_CLIENT_ID) names one. Once prod has a client,
# set it here and prod signs in too.
if [[ "$NDP_ENV" == "test" ]]; then
  LOGIN_ISSUER="https://idp-test.nationaldataplatform.org/realms/NDP"
  LOGIN_CLIENT_ID="${LOGIN_CLIENT_ID:-ep-installer-testing}"
else
  LOGIN_ISSUER="https://idp.nationaldataplatform.org/realms/NDP"
fi
DEVICE_GRANT="urn:ietf:params:oauth:grant-type:device_code"
NDP_TOKEN=""

# ---- Output --------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  BOLD="";         RESET=""
fi
fail() { echo "Error: $*" >&2; exit 1; }

# ---- Private scratch space -----------------------------------------------
AUTH_DIR="$(mktemp -d)"
chmod 700 "$AUTH_DIR"
trap 'rm -rf "$AUTH_DIR"' EXIT

# ---- HTTP helpers --------------------------------------------------------
# request OUT URL [curl args...]
#   Calls URL, leaves the body in $AUTH_DIR/OUT and prints the HTTP status
#   (000 when there was no answer).
request() {
  local out="$AUTH_DIR/$1" url="$2" code
  shift 2
  code="$(curl -s -m 30 -o "$out" -w '%{http_code}' "$@" "$url" 2>/dev/null)" || true
  [[ "$code" =~ ^[1-5][0-9][0-9]$ ]] || code="000"
  echo "$code"
}

# field FILE FILTER
#   The jq FILTER applied to $AUTH_DIR/FILE; empty when FILE is not JSON.
field() { jq -r "$2" "$AUTH_DIR/$1" 2>/dev/null || true; }

# ---- Device flow ---------------------------------------------------------
# ndp_login
#   Signs the person in and sets NDP_TOKEN, or stops the script saying why.
ndp_login() {
  local code token_url device_url device_code user_code link
  local interval expires_in deadline error who

  # 1. The realm's endpoints, then a device code and a user code.
  code="$(request oidc.json "${LOGIN_ISSUER}/.well-known/openid-configuration")"
  [[ "$code" == "200" ]] \
    || fail "Could not read the sign-in settings of ${LOGIN_ISSUER} (HTTP ${code})."
  token_url="$(field oidc.json '.token_endpoint // empty')"
  device_url="$(field oidc.json '.device_authorization_endpoint // empty')"
  [[ -n "$token_url" && -n "$device_url" ]] \
    || fail "${LOGIN_ISSUER} does not offer the device flow."

  code="$(request device.json "$device_url" \
    --data-urlencode "client_id=${LOGIN_CLIENT_ID}" \
    --data-urlencode "scope=openid")"
  device_code="$(field device.json '.device_code // empty')"
  if [[ "$code" != "200" || -z "$device_code" ]]; then
    error="$(field device.json '.error_description // .error // empty')"
    fail "The identity provider would not start a sign-in for client '${LOGIN_CLIENT_ID}' (HTTP ${code})${error:+: ${error}}."
  fi
  # Whoever holds the device code can collect the token: keep it in a file.
  printf '%s' "$device_code" > "$AUTH_DIR/device_code"

  user_code="$(field device.json '.user_code // empty')"
  link="$(field device.json '.verification_uri_complete // .verification_uri // empty')"
  interval="$(field device.json '.interval // 5')"
  expires_in="$(field device.json '.expires_in // 600')"
  [[ "$interval"   =~ ^[0-9]+$ ]] || interval=5
  [[ "$expires_in" =~ ^[0-9]+$ ]] || expires_in=600

  # 2. Show the person where to sign in.
  echo "==> Sign in to NDP to read the federation config"
  echo ""
  echo "      Open in a browser:  ${BOLD}${link}${RESET}"
  echo "      Code:               ${BOLD}${user_code}${RESET}"
  echo ""
  echo "    Waiting for you to sign in (the code expires in $(( expires_in >= 60 ? expires_in / 60 : 1 )) min)..."

  # 3. Poll until signed in, declined or expired; slower on slow_down
  #    (RFC 8628 section 3.5).
  deadline=$(( SECONDS + expires_in ))
  while :; do
    sleep "$interval"
    code="$(request token.json "$token_url" \
      --data-urlencode "grant_type=${DEVICE_GRANT}" \
      --data-urlencode "client_id=${LOGIN_CLIENT_ID}" \
      --data-urlencode "device_code@${AUTH_DIR}/device_code")"
    if [[ "$code" == "200" ]]; then
      NDP_TOKEN="$(field token.json '.access_token // empty')"
      rm -f "$AUTH_DIR/token.json"
      [[ -n "$NDP_TOKEN" ]] && break
    fi
    error="$(field token.json '.error // empty')"
    case "$error" in
      authorization_pending) ;;
      slow_down)     interval=$(( interval + 5 )) ;;
      access_denied) fail "Sign-in was declined in the browser." ;;
      expired_token) fail "The sign-in code expired; run the script again." ;;
      *)             fail "The identity provider refused the sign-in (HTTP ${code})${error:+: ${error}}." ;;
    esac
    (( SECONDS < deadline )) || fail "The sign-in code expired; run the script again."
  done

  # Who signed in, read from the token for display only (the Federation
  # verifies it).
  who="$(printf '%s' "$NDP_TOKEN" | jq -rR '
    split(".")[1] | gsub("-"; "+") | gsub("_"; "/")
    | . + ("=" * ((4 - length % 4) % 4)) | @base64d | fromjson
    | (.preferred_username // "?") + (if .email then " <\(.email)>" else "" end)
  ' 2>/dev/null)" || true
  echo "==> Signed in${who:+ as ${who}}"
}

# ---- Federation call -----------------------------------------------------
# fetch_federation_config
#   GET /ep/{config_id}, with "Authorization: Bearer <token>" when there is a
#   token. Prints the configuration, or stops the script with the reason.
fetch_federation_config() {
  local code url="${FEDERATION_URL}/ep/${CONFIG_ID}"

  if [[ -n "$NDP_TOKEN" ]]; then
    printf 'Authorization: Bearer %s\n' "$NDP_TOKEN" > "$AUTH_DIR/auth_header"
    code="$(request config.json "$url" -H "@${AUTH_DIR}/auth_header")"
    rm -f "$AUTH_DIR/auth_header"
  else
    code="$(request config.json "$url")"
  fi

  case "$code" in
    200) cat "$AUTH_DIR/config.json" ;;
    401|403)
      if [[ -z "$NDP_TOKEN" ]]; then
        fail "The Federation answers ${CONFIG_ID} only to an admin of the Endpoint (HTTP ${code}). Pass --ndp-token-file <path>, or --login-client-id <id> to sign in."
      elif [[ "$code" == "401" ]]; then
        fail "The Federation did not accept your NDP token (HTTP 401). Get a fresh one and try again."
      else
        fail "Your NDP account is not an admin of Endpoint configuration ${CONFIG_ID} (HTTP 403)."
      fi ;;
    404) fail "Configuration ${CONFIG_ID} not found at ${FEDERATION_URL}. Check --config-id and --env." ;;
    000) fail "Could not reach the Federation at ${FEDERATION_URL}." ;;
    *)   fail "The Federation answered HTTP ${code} for configuration ${CONFIG_ID}." ;;
  esac
}

# ---- Get the token -------------------------------------------------------
if [[ -n "$NDP_TOKEN_FILE" ]]; then
  [[ -r "$NDP_TOKEN_FILE" ]] || fail "Cannot read the NDP token file: ${NDP_TOKEN_FILE}"
  NDP_TOKEN="$(tr -d '[:space:]' < "$NDP_TOKEN_FILE")"
  [[ -n "$NDP_TOKEN" ]] || fail "The NDP token file is empty: ${NDP_TOKEN_FILE}"
  echo "==> Using the NDP token from ${NDP_TOKEN_FILE}"
elif [[ -n "$LOGIN_CLIENT_ID" ]]; then
  ndp_login
else
  echo "==> No login client for --env ${NDP_ENV}: asking the Federation without a token"
fi

# --------------------------------------------------------------------------
# Pre-fetch federation doc to determine optional sub-charts
# --------------------------------------------------------------------------
echo "==> Fetching federation config: ${FEDERATION_URL}/ep/${CONFIG_ID}"
DOC="$(fetch_federation_config)"

STREAMING="$(echo "$DOC" | jq -r '.streaming // false')"
JHUB="$(echo "$DOC"      | jq -r '.jhub      // false')"
REXEC="$(echo "$DOC"     | jq -r '.rexec     // false')"

KAFKA_ENABLED="false"
if [[ "$STREAMING" == "true" || "$STREAMING" == "True" ]]; then
  KAFKA_ENABLED="true"
fi

JHUB_ENABLED="false"
if [[ "$JHUB" == "true" || "$JHUB" == "True" ]]; then
  JHUB_ENABLED="true"
fi

REXEC_ENABLED="false"
if [[ "$REXEC" == "true" || "$REXEC" == "True" ]]; then
  REXEC_ENABLED="true"
fi

echo "==> streaming=${STREAMING}   -> kafka-kraft.enabled=${KAFKA_ENABLED}"
echo "==> jupyterhub=${JHUB}       -> ndp-jupyterhub.enabled=${JHUB_ENABLED}"
echo "==> rexec=${REXEC}           -> rexec-broker.enabled=${REXEC_ENABLED}, rexec-server-deployment-api.enabled=${REXEC_ENABLED}"

# --------------------------------------------------------------------------
# Add/update Helm repo
# --------------------------------------------------------------------------
helm repo add ndp-ep https://sci-ndp.github.io/ndp-ep-helm
helm repo update

# --------------------------------------------------------------------------
# Deploy
# --------------------------------------------------------------------------
helm upgrade --install "${RELEASE_NAME}" ndp-ep/ndp-ep-helm \
  -n "${NAMESPACE}" --create-namespace \
  --set global.env="${NDP_ENV}" \
  --set federation.configId="${CONFIG_ID}" \
  --set global.clusterHost="${CLUSTER_HOST}" \
  --set global.clusterPublicHost="${CLUSTER_PUBLIC_HOST}" \
  --set global.clusterStorageClass="${STORAGE_CLASS}" \
  --set global.clusterIngressClass="${INGRESS_CLASS}" \
  --set kafka-kraft.enabled="${KAFKA_ENABLED}" \
  --set ndp-jupyterhub.enabled="${JHUB_ENABLED}" \
  --set rexec-broker.enabled="${REXEC_ENABLED}" \
  --set rexec-server-deployment-api.enabled="${REXEC_ENABLED}"
