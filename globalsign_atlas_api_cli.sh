#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# GlobalSign Atlas API CLI
# Developped by: Christ ND 
# Doc: https://api.docs.globalsign.com/docs/category/hvca
# 
# Purpose
  # This project is designed to provide additional flexibility 
  # and options for managing your certificates. 
  # It is not intended to replace any existing tools you may already be using, 
  # but rather to complement them and expand your available workflows.
# ============================================================

# =========================
# Load .env file
# =========================

if [ -f .env ]; then
  set -a
  source .env
  set +a
else
  echo ".env file not found or empty. Continuing with prompt input..."
fi

# =========================
# Config
# =========================

BASE_URL="${BASE_URL:-https://emea.api.hvca.globalsign.com:8443/v2}"
MTLS_CERT="${MTLS_CERT:-yourmTLShere.pem}"
MTLS_KEY="${MTLS_KEY:-yourmTLSprivatekeyhere.key}"
REQUEST_JSON="${REQUEST_JSON:-request.json}"
REISSUE_JSON="${REISSUE_JSON:-reissue.json}"

API_KEY="${API_KEY:-}"
API_SECRET="${API_SECRET:-}"

MAX_POLLS="${MAX_POLLS:-30}"
SLEEP_SECONDS="${SLEEP_SECONDS:-5}"
OUT_DIR="${OUT_DIR:-./output}"
IP_CLAIMS_BASE="${IP_CLAIMS_BASE:-/claims/ipaddresses}"

mkdir -p "$OUT_DIR"

# ========================= 
# Runtime vars
# =========================

LOGIN_BODY=""
RESP_BODY=""
RESP_HEADERS=""
ISSUE_BODY=""
ISSUE_HEADERS=""
CERT_BODY=""
CHAIN_BODY=""
ACCESS_TOKEN=""
HTTP_CODE=""

# =========================
# ANSI Colors
# =========================

RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'

# =========================
# Helpers
# =========================

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

cleanup() {
  rm -f "${LOGIN_BODY:-}" "${RESP_BODY:-}" "${RESP_HEADERS:-}" \
        "${ISSUE_BODY:-}" "${ISSUE_HEADERS:-}" "${CERT_BODY:-}" "${CHAIN_BODY:-}" \
        "${NORMALIZED_REQUEST_JSON:-}" "${REISSUE_JSON:-}"
}
trap cleanup EXIT

clear_screen() {
  printf '\033[2J\033[H'
}

type_text() {
  local text="$1"
  local delay="${2:-0.008}"
  local i ch
  for ((i=0; i<${#text}; i++)); do
    ch="${text:$i:1}"
    printf '%s' "$ch"
    sleep "$delay"
  done
  printf '\n'
}

space() {
  echo
}

divider() {
  printf "%b%s%b\n" "$DIM" "------------------------------------------------------------" "$RESET"
}

# spinner() {
#   local pid="$1"
#   local message="${2:-Loading}"
#   local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
#   local i=0

#   while kill -0 "$pid" 2>/dev/null; do
#     printf '\r%b%s%b %s' "$CYAN$BOLD" "${frames[$i]}" "$RESET" "$message"
#     i=$(( (i + 1) % ${#frames[@]} ))
#     sleep 0.10
#   done
# }

# run_with_spinner() {
#   local message="$1"
#   shift

#   "$@" &
#   local pid=$!

#   spinner "$pid" "$message"
#   wait "$pid"
#   local rc=$?

#   printf '\r\033[K'
#   if [[ $rc -eq 0 ]]; then
#     printf "%b✔%b %s\n" "$GREEN$BOLD" "$RESET" "$message"
#   else
#     printf "%b✖%b %s\n" "$RED$BOLD" "$RESET" "$message"
#   fi

#   return "$rc"
# }

progress_wait() {
  local seconds="$1"
  local message="${2:-Waiting}"
  local width=24
  local elapsed filled empty bar

  for ((elapsed=1; elapsed<=seconds; elapsed++)); do
    filled=$(( elapsed * width / seconds ))
    empty=$(( width - filled ))
    bar="$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' "$empty" '')"
    space
    printf '\r%b[%s]%b %s %ds/%ds' "$BLUE$BOLD" "$bar" "$RESET" "$message" "$elapsed" "$seconds"
    sleep 1
  done
  printf '\n'
}

print_kv() {
  local key="$1"
  local value="$2"
  printf "%b%-20s%b %s\n" "$CYAN$BOLD" "$key" "$RESET" "$value"
}

print_info() {
  printf "%b➜ %b%s\n" "$CYAN$BOLD" "$RESET" "$1"
}

print_ok() {
  printf "%b✔ %b%s\n" "$GREEN$BOLD" "$RESET" "$1"
}

print_warn() {
  printf "%b! %b%s\n" "$YELLOW$BOLD" "$RESET" "$1"
}

print_err() {
  printf "%b✖ %b%s\n" "$RED$BOLD" "$RESET" "$1" >&2
}

pause() {
  echo
  read -r -p "Press Enter to continue..." _
}

prompt_if_empty() {
  local var_name="$1"
  local prompt_text="$2"
  local secret="${3:-false}"
  local current_value="${!var_name:-}"

  if [[ -z "$current_value" ]]; then
    if [[ "$secret" == "true" ]]; then
      read -r -s -p "$prompt_text: " current_value
      echo
    else
      read -r -p "$prompt_text: " current_value
    fi
    printf -v "$var_name" '%s' "$current_value"
    export "$var_name"
  fi
}

ensure_config() {
  require_cmd curl
  require_cmd jq
  require_cmd awk
  require_cmd tr
  require_cmd sed
  require_cmd python3

  prompt_if_empty BASE_URL "Enter BASE_URL [e.g. https://emea.api.hvca.globalsign.com:8443/v2]"
  prompt_if_empty MTLS_CERT "Enter path to mTLS certificate file"
  prompt_if_empty MTLS_KEY "Enter path to mTLS private key file"
  prompt_if_empty API_KEY "Enter your API_KEY" true
  prompt_if_empty API_SECRET "Enter your API_SECRET" true

  [[ -f "$MTLS_CERT" ]] || { echo "mTLS cert file not found: $MTLS_CERT" >&2; exit 1; }
  [[ -f "$MTLS_KEY" ]] || { echo "mTLS key file not found: $MTLS_KEY" >&2; exit 1; }
}

banner() {
  cat <<'EOF'
███████████████████████████████████████████████████████████████████████████████████████

     ██████╗ ██╗      ██████╗ ██████╗  █████╗ ██╗     ███████╗██╗ ██████╗ ███╗   ██╗
    ██╔════╝ ██║     ██╔═══██╗██╔══██╗██╔══██╗██║     ██╔════╝██║██╔════╝ ████╗  ██║
    ██║  ███╗██║     ██║   ██║██████╔╝███████║██║     ███████╗██║██║  ███╗██╔██╗ ██║
    ██║   ██║██║     ██║   ██║██╔══██╗██╔══██║██║     ╚════██║██║██║   ██║██║╚██╗██║
    ╚██████╔╝███████╗╚██████╔╝██████╔╝██║  ██║███████╗███████║██║╚██████╔╝██║ ╚████║
     ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝ by ⓒⓗⓡⓘⓢⓣⓝⓓ

███████████████████████████████████████████████████████████████████████████████████████
EOF
}

welcome() {
  clear_screen
  printf "%b" "$BLUE$BOLD"
  banner
  printf "%b\n" "$RESET"
  type_text "Welcome to the GlobalSign Atlas Unified CLI." 0.009
  type_text "Made with ❤️ by Christ ND." 0.012
  echo
}

goodbye() {
  clear_screen
  printf "%b" "$RED$BOLD"
  banner
  printf "%b\n" "$RESET"
  type_text "Session closed." 0.010
  type_text "Goodbye, and thank you for choosing GlobalSign." 0.011
  echo
}

section_header() {
  local title="$1"
  clear_screen
  printf "%b" "$CYAN$BOLD"
  banner
  printf "%b\n\n" "$RESET"
  printf "%b== %s ==%b\n\n" "$YELLOW$BOLD" "$title" "$RESET"
}

print_response() {
  echo
  printf "%bHTTP %s%b\n" "$YELLOW$BOLD" "$HTTP_CODE" "$RESET"
  printf "%b%s%b\n" "$DIM" "------------------------------------------------------------" "$RESET"
  if [[ -s "$RESP_BODY" ]]; then
    if jq . < "$RESP_BODY" >/dev/null 2>&1; then
      jq . < "$RESP_BODY"
    else
      cat "$RESP_BODY"
    fi
  else
    echo "(This response does not return a body)"
  fi
  printf "%b%s%b\n" "$DIM" "------------------------------------------------------------" "$RESET"
}

read_claim_id() {
  local claim_id
  read -r -p "Enter claim ID: " claim_id
  if [[ -z "$claim_id" ]]; then
    echo "Claim ID is required." >&2
    return 1
  fi
  printf '%s' "$claim_id"
}

read_nonempty() {
  local prompt="$1"
  local value
  read -r -p "$prompt: " value
  if [[ -z "$value" ]]; then
    echo "This field is required." >&2
    return 1
  fi
  printf '%s' "$value"
}

# =========================
# Shared login/api
# =========================

login() {
  LOGIN_BODY="$(mktemp)"

  echo
  echo "Logging in to Atlas..."

  local login_payload
  login_payload="$(
    jq -nc \
      --arg key "$API_KEY" \
      --arg secret "$API_SECRET" \
      '{api_key:$key, api_secret:$secret}'
  )"

  local login_http_code
  login_http_code="$(
    curl -sS \
      --cert "$MTLS_CERT" \
      --key "$MTLS_KEY" \
      -o "$LOGIN_BODY" \
      -w "%{http_code}" \
      -H "Content-Type: application/json; charset=utf-8" \
      -H "Accept: application/json" \
      --data-binary "$login_payload" \
      "$BASE_URL/login"
  )"

  if [[ "$login_http_code" != "200" && "$login_http_code" != "201" ]]; then
    echo "Login failed. HTTP $login_http_code" >&2
    echo "Response body:" >&2
    cat "$LOGIN_BODY" >&2
    echo >&2
    return 1
  fi

  ACCESS_TOKEN="$(jq -r '.access_token // empty' "$LOGIN_BODY")"
  if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "Login succeeded but no access_token was returned." >&2
    cat "$LOGIN_BODY" >&2
    return 1
  fi

  echo "Login Successful."
}

api_call() {
  local method="$1"
  local endpoint="$2"
  local body="${3:-}"
  local content_type="${4:-application/json;charset=utf-8}"

  RESP_BODY="$(mktemp)"
  RESP_HEADERS="$(mktemp)"

  local curl_args=(
    -sS
    --cert "$MTLS_CERT"
    --key "$MTLS_KEY"
    -D "$RESP_HEADERS"
    -o "$RESP_BODY"
    -w "%{http_code}"
    -X "$method"
    -H "Accept: application/json"
    -H "Authorization: Bearer $ACCESS_TOKEN"
  )

  if [[ -n "$body" ]]; then
    curl_args+=(
      -H "Content-Type: $content_type"
      --data-binary "$body"
    )
  fi

  HTTP_CODE="$(curl "${curl_args[@]}" "$BASE_URL$endpoint")"
}

# animated_login() {
#   printf "%b⏳ %b%s\n" "$CYAN$BOLD" "$RESET" "Authenticating to Atlas..."
#   login
#   local rc=$?
#   if [[ $rc -eq 0 ]]; then
#     printf "%b✔ %b%s\n" "$GREEN$BOLD" "$RESET" "Authenticating to Atlas"
#   else
#     printf "%b✖ %b%s\n" "$RED$BOLD" "$RESET" "Authenticating to Atlas"
#   fi
#   return $rc
# }

# animated_api_call() {
#   local method="$1"
#   local endpoint="$2"
#   local body="${3:-}"
#   local message="${4:-Processing request}"

#   printf "%b⏳ %b%s\n" "$CYAN$BOLD" "$RESET" "$message"
#   api_call "$method" "$endpoint" "$body"
#   local rc=$?

#   if [[ $rc -eq 0 ]]; then
#     printf "%b✔ %b%s\n" "$GREEN$BOLD" "$RESET" "$message"
#   else
#     printf "%b✖ %b%s\n" "$RED$BOLD" "$RESET" "$message"
#   fi
#   return $rc
# }

# =========================
# Json parsing
# =========================

normalize_request_json() {
  local input_file="$1"
  local output_file="$2"
  local now_utc="$3"
  local not_after_utc="${4:-}"

  python3 - "$input_file" "$output_file" "$now_utc" "$not_after_utc" <<'PY'
import sys
import re
import json

input_file = sys.argv[1]
output_file = sys.argv[2]
now_utc = int(sys.argv[3])
not_after_raw = sys.argv[4].strip()

with open(input_file, "r", encoding="utf-8") as f:
    raw = f.read()

# Normalize raw multiline public_key into a valid JSON string
pattern = r'("public_key"\s*:\s*")(.+?)(")'
match = re.search(pattern, raw, flags=re.DOTALL)

if match:
    prefix, value, suffix = match.groups()
    escaped_value = json.dumps(value)[1:-1]
    raw = raw[:match.start()] + prefix + escaped_value + suffix + raw[match.end():]

data = json.loads(raw)

data.setdefault("validity", {})
data["validity"]["not_before"] = now_utc

# Only inject not_after when provided and > 0
if not_after_raw and not_after_raw != "0":
    data["validity"]["not_after"] = int(not_after_raw)
else:
    data["validity"].pop("not_after", None)

with open(output_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

# =========================
# Issuing certificates
# =========================

auto_issuance() {
  section_header "Issuing Certificates"

  if [[ ! -f "$REQUEST_JSON" ]]; then
    print_err "Missing file: $REQUEST_JSON"
    pause
    return 0
  fi

  ISSUE_BODY="$(mktemp)"
  ISSUE_HEADERS="$(mktemp)"
  CERT_BODY="$(mktemp)"
  CHAIN_BODY="$(mktemp)"

  print_info "Starting certificate issuance workflow"

  login || {
    print_err "Authentication failed."
    pause
    return 0
  }

  # ============================================================
  # Inject current UTC Unix timestamp into request.json
  # ============================================================

  local NOW_UTC NORMALIZED_REQUEST_JSON NOT_AFTER_DAYS NOT_AFTER_UTC
  NOW_UTC="$(date -u +%s)"
  NORMALIZED_REQUEST_JSON="$(mktemp)"

  read -r -p "Enter certificate validity in days for not_after [blank = default max policy]: " NOT_AFTER_DAYS

  NOT_AFTER_UTC=""
  if [[ -n "${NOT_AFTER_DAYS:-}" && "$NOT_AFTER_DAYS" != "0" ]]; then
    if [[ ! "$NOT_AFTER_DAYS" =~ ^[0-9]+$ ]]; then
      print_err "not_after days must be a whole number."
      pause
      return 0
    fi
    NOT_AFTER_UTC="$((NOW_UTC + NOT_AFTER_DAYS * 86400))"
  fi

  if ! normalize_request_json "$REQUEST_JSON" "$NORMALIZED_REQUEST_JSON" "$NOW_UTC" "$NOT_AFTER_UTC"; then
    print_err "Failed to normalize and update $REQUEST_JSON"
    pause
    return 0
  fi

  print_info "Injected not_before (UTC): $NOW_UTC"
  if [[ -n "$NOT_AFTER_UTC" ]]; then
    print_info "Injected not_after (UTC): $NOT_AFTER_UTC (${NOT_AFTER_DAYS} day(s))"
  else
    print_info "not_after left unset; Atlas will use validation policy maximum"
  fi
  print_info "Using temp request file: $NORMALIZED_REQUEST_JSON"

  local issue_http_code
  issue_http_code="$(
    curl -sS \
      --cert "$MTLS_CERT" \
      --key "$MTLS_KEY" \
      -D "$ISSUE_HEADERS" \
      -o "$ISSUE_BODY" \
      -w "%{http_code}" \
      -H "Content-Type: application/json; charset=utf-8" \
      -H "Accept: application/json" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      --data-binary @"$NORMALIZED_REQUEST_JSON" \
      "$BASE_URL/certificates"
  )"

  if [[ "$issue_http_code" != "200" && "$issue_http_code" != "201" && "$issue_http_code" != "202" ]]; then
    print_err "Certificate request failed. HTTP $issue_http_code"
    if [[ -s "$ISSUE_BODY" ]]; then
      echo
      if jq . < "$ISSUE_BODY" >/dev/null 2>&1; then
        jq . < "$ISSUE_BODY"
      else
        cat "$ISSUE_BODY"
      fi
    fi
    pause
    return 0
  fi

  local cert_url cert_serial
  cert_url="$(
    awk 'BEGIN{IGNORECASE=1} /^Location:/ {print $2}' "$ISSUE_HEADERS" \
      | tr -d '\r' \
      | tail -n 1
  )"

  if [[ -z "$cert_url" ]]; then
    print_err "Request succeeded but no Location header was returned."
    if [[ -s "$ISSUE_BODY" ]]; then
      echo
      if jq . < "$ISSUE_BODY" >/dev/null 2>&1; then
        jq . < "$ISSUE_BODY"
      else
        cat "$ISSUE_BODY"
      fi
    fi
    pause
    return 0
  fi

  cert_serial="${cert_url##*/}"

  if [[ -z "$cert_serial" ]]; then
    print_err "Could not parse certificate serial from Location header: $cert_url"
    pause
    return 0
  fi

  space
  print_ok " Certificate request accepted"
  print_kv " Certificate URL" "$cert_url"
  print_kv " Certificate serial" "$cert_serial"
  divider
  space

  local cert_file cert_json_file
  cert_file="$OUT_DIR/${cert_serial}.crt"
  cert_json_file="$OUT_DIR/${cert_serial}.json"

  space
  divider
  print_info "Polling certificate status"
  space
  divider

  local cert_ready=0
  local i cert_http_code cert_status cert_pem
  for ((i=1; i<=MAX_POLLS; i++)); do
    cert_http_code="$(
      curl -sS \
        --cert "$MTLS_CERT" \
        --key "$MTLS_KEY" \
        -o "$CERT_BODY" \
        -w "%{http_code}" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "$BASE_URL/certificates/$cert_serial"
    )"

    space
    divider
    printf "%bPoll %d/%d%b\n" "$YELLOW$BOLD" "$i" "$MAX_POLLS" "$RESET"
    printf "%bHTTP %s%b\n" "$YELLOW$BOLD" "$cert_http_code" "$RESET"
    divider

    if [[ "$cert_http_code" == "200" ]]; then
      cp "$CERT_BODY" "$cert_json_file"

      cert_status="$(jq -r '.status // empty' "$CERT_BODY")"
      cert_pem="$(jq -r '.certificate // empty' "$CERT_BODY")"

      print_kv "Status" "${cert_status:-unknown}"
      space

      if [[ -s "$CERT_BODY" ]]; then
        if jq . < "$CERT_BODY" >/dev/null 2>&1; then
          jq . < "$CERT_BODY"
        else
          cat "$CERT_BODY"
        fi
      fi

      if [[ -n "$cert_pem" && "$cert_pem" != "null" ]]; then
        printf '%s\n' "$cert_pem" > "$cert_file"
        cert_ready=1
        space
        divider
        print_ok " Certificate saved to: $cert_file"
        divider
        break
      fi
    else
      if [[ -s "$CERT_BODY" ]]; then
        if jq . < "$CERT_BODY" >/dev/null 2>&1; then
          jq . < "$CERT_BODY"
        else
          cat "$CERT_BODY"
        fi
      fi
    fi

    if (( i < MAX_POLLS )); then
      progress_wait "$SLEEP_SECONDS" "Waiting before next poll"
    fi
  done

  if [[ "$cert_ready" -ne 1 ]]; then
    space
    divider
    print_err "Certificate was not returned within polling window."
    print_kv "Last response saved to" "$cert_json_file"
    divider
    space
    pause
    return 0
  fi

  echo
  print_info "Retrieving trust chain"

  local chain_http_code
  chain_http_code="$(
    curl -sS \
      --cert "$MTLS_CERT" \
      --key "$MTLS_KEY" \
      -o "$CHAIN_BODY" \
      -w "%{http_code}" \
      -H "Accept: application/json" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      "$BASE_URL/trustchain"
  )"

  if [[ "$chain_http_code" != "200" ]]; then
    print_err "Trust chain retrieval failed. HTTP $chain_http_code"
    if [[ -s "$CHAIN_BODY" ]]; then
      if jq . < "$CHAIN_BODY" >/dev/null 2>&1; then
        jq . < "$CHAIN_BODY"
      else
        cat "$CHAIN_BODY"
      fi
    fi
    pause
    return 0
  fi

  local chain_file fullchain_file chain_json_file
  chain_file="$OUT_DIR/chain.pem"
  fullchain_file="$OUT_DIR/fullchain.pem"
  chain_json_file="$OUT_DIR/trustchain.json"

  cp "$CHAIN_BODY" "$chain_json_file"
  jq -r '.[]?' "$CHAIN_BODY" > "$chain_file"

  if [[ ! -s "$chain_file" ]]; then
    print_err "Trust chain response did not look like a JSON array of PEM strings."
    print_kv "Saved raw response to" "$chain_json_file"
    pause
    return 0
  fi

  cat "$cert_file" "$chain_file" > "$fullchain_file"

  space
  print_ok " Certificate issuance workflow completed"
  divider
  print_kv " Certificate serial" "$cert_serial"
  print_kv " Certificate file" "$cert_file"
  print_kv " Chain file" "$chain_file"
  print_kv " Fullchain file" "$fullchain_file"
  print_kv " Cert JSON" "$cert_json_file"
  print_kv " Chain JSON" "$chain_json_file"
  space
  divider
  pause
  return 0
}

request_new_certificate() {
  section_header "Request a New Certificate"

  if [[ ! -f "$REQUEST_JSON" ]]; then
    print_err "Missing file: $REQUEST_JSON"
    pause
    return 0
  fi

  login || { pause; return 0; }

  # ============================================================
  # Inject current UTC Unix timestamp into request.json
  # ============================================================

  local NOW_UTC NORMALIZED_REQUEST_JSON NOT_AFTER_DAYS NOT_AFTER_UTC
  NOW_UTC="$(date -u +%s)"
  NORMALIZED_REQUEST_JSON="$(mktemp)"

  read -r -p "Enter certificate validity in days for not_after [blank = default max policy]: " NOT_AFTER_DAYS

  NOT_AFTER_UTC=""
  if [[ -n "${NOT_AFTER_DAYS:-}" && "$NOT_AFTER_DAYS" != "0" ]]; then
    if [[ ! "$NOT_AFTER_DAYS" =~ ^[0-9]+$ ]]; then
      print_err "not_after days must be a whole number."
      pause
      return 0
    fi
    NOT_AFTER_UTC="$((NOW_UTC + NOT_AFTER_DAYS * 86400))"
  fi

  if ! normalize_request_json "$REQUEST_JSON" "$NORMALIZED_REQUEST_JSON" "$NOW_UTC" "$NOT_AFTER_UTC"; then
    print_err "Failed to normalize and update $REQUEST_JSON"
    pause
    return 0
  fi

  print_info "Injected not_before (UTC): $NOW_UTC"
  if [[ -n "$NOT_AFTER_UTC" ]]; then
    print_info "Injected not_after (UTC): $NOT_AFTER_UTC (${NOT_AFTER_DAYS} day(s))"
  else
    print_info "not_after left unset; Atlas will use validation policy maximum"
  fi
  print_info "Using temp request file: $NORMALIZED_REQUEST_JSON"

  RESP_BODY="$(mktemp)"
  RESP_HEADERS="$(mktemp)"

  HTTP_CODE="$(
    curl -sS \
      --cert "$MTLS_CERT" \
      --key "$MTLS_KEY" \
      -D "$RESP_HEADERS" \
      -o "$RESP_BODY" \
      -w "%{http_code}" \
      -H "Content-Type: application/json; charset=utf-8" \
      -H "Accept: application/json" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      --data-binary @"$NORMALIZED_REQUEST_JSON" \
      "$BASE_URL/certificates"
  )"

  echo
  print_response

  local location cert_serial
  location="$(awk 'BEGIN{IGNORECASE=1} /^Location:/ {print $2}' "$RESP_HEADERS" | tr -d '\r' | tail -n 1)"
  cert_serial="${location##*/}"

  if [[ -n "$location" ]]; then
    space
    print_kv "Location" "$location"
  fi

  if [[ -n "$cert_serial" && "$cert_serial" != "$location" ]]; then
    print_kv "Certificate ID" "$cert_serial"
  fi

  pause
  return 0
}

get_certificate_by_id() {
  section_header "Get Certificate by ID"

  local cert_id
  cert_id="$(read_nonempty "Enter certificate ID / serial")" || { pause; return 0; }

  login || { pause; return 0; }
  api_call GET "/certificates/$cert_id" "" "Retrieving certificate"
  print_response

  if [[ "$HTTP_CODE" == "200" && -s "$RESP_BODY" ]]; then
    local cert_pem cert_file cert_json_file
    cert_pem="$(jq -r '.certificate // empty' "$RESP_BODY")"

    cert_json_file="$OUT_DIR/${cert_id}.json"
    cp "$RESP_BODY" "$cert_json_file"

    if [[ -n "$cert_pem" && "$cert_pem" != "null" ]]; then
      cert_file="$OUT_DIR/${cert_id}.crt"
      printf '%s\n' "$cert_pem" > "$cert_file"

      echo
      print_ok " Certificate saved to: $cert_file"
      print_kv " Certificate JSON" "$cert_json_file"
    else
      echo
      print_warn "No certificate PEM found in response."
      print_kv " Response JSON saved to" "$cert_json_file"
    fi
  fi

  pause
  return 0
}

revoke_certificate_by_id() {
  section_header "Revoke Certificate by ID"

  local cert_id revocation_reason payload
  cert_id="$(read_nonempty "Enter certificate ID / serial")" || { pause; return 0; }

  cat <<'EOF'
Revocation reasons:
1) unspecified
2) keyCompromise
3) affiliationChanged
4) cessationOfOperation
5) superseded
EOF

  local reason_choice
  read -r -p "Select revocation reason [1-5]: " reason_choice

  case "$reason_choice" in
    1) revocation_reason="unspecified" ;;
    2) revocation_reason="keyCompromise" ;;
    3) revocation_reason="affiliationChanged" ;;
    4) revocation_reason="cessationOfOperation" ;;
    5) revocation_reason="superseded" ;;
    *) print_err "Invalid revocation reason." ; pause ; return 0 ;;
  esac

  if [[ "$revocation_reason" == "keyCompromise" ]]; then
    local revocation_time attestation_file attestation_data
    read -r -p "Enter revocation_time UNIX timestamp [blank = now]: " revocation_time
    revocation_time="${revocation_time:-$(date +%s)}"

    read -r -p "Enter key compromise attestation CSR file path [optional]: " attestation_file

    if [[ -n "$attestation_file" ]]; then
      if [[ ! -f "$attestation_file" ]]; then
        print_err "Attestation file not found: $attestation_file"
        pause
        return 0
      fi

      attestation_data="$(cat "$attestation_file")"
      payload="$(
        jq -n \
          --arg revocation_reason "$revocation_reason" \
          --argjson revocation_time "$revocation_time" \
          --arg key_compromise_attestation "$attestation_data" \
          '{
            revocation_reason: $revocation_reason,
            revocation_time: $revocation_time,
            key_compromise_attestation: $key_compromise_attestation
          }'
      )"
    else
      payload="$(
        jq -n \
          --arg revocation_reason "$revocation_reason" \
          --argjson revocation_time "$revocation_time" \
          '{
            revocation_reason: $revocation_reason,
            revocation_time: $revocation_time
          }'
      )"
    fi
  else
    payload="$(
      jq -n \
        --arg revocation_reason "$revocation_reason" \
        '{revocation_reason: $revocation_reason}'
    )"
  fi

  login || { pause; return 0; }
  api_call PATCH "/certificates/$cert_id" "$payload" "Revoking certificate"
  print_response
  pause
  return 0
}

rekey_certificate() {
  section_header "Rekey / Reissue Certificate"

  local cert_id
  cert_id="$(read_nonempty "Enter certificate ID / serial")" || { pause; return 0; }

  if [[ ! -f "$REISSUE_JSON" ]]; then
    print_err "Missing file: $REISSUE_JSON"
    pause
    return 0
  fi

  login || { pause; return 0; }

  RESP_BODY="$(mktemp)"
  RESP_HEADERS="$(mktemp)"

  HTTP_CODE="$(
    curl -sS \
      --cert "$MTLS_CERT" \
      --key "$MTLS_KEY" \
      -D "$RESP_HEADERS" \
      -o "$RESP_BODY" \
      -w "%{http_code}" \
      -X POST \
      -H "Content-Type: application/json;charset=utf-8" \
      -H "Accept: application/json" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      --data-binary @"$REISSUE_JSON" \
      "$BASE_URL/certificates/$cert_id/rekey"
  )"

  print_response

  local location new_cert_id
  location="$(awk 'BEGIN{IGNORECASE=1} /^Location:/ {print $2}' "$RESP_HEADERS" | tr -d '\r' | tail -n 1)"
  new_cert_id="${location##*/}"

  if [[ -n "$location" ]]; then
    echo
    print_kv "Location" "$location"
  fi

  if [[ -n "$new_cert_id" && "$new_cert_id" != "$location" ]]; then
    print_kv "New Certificate ID" "$new_cert_id"
  fi

  pause
  return 0
}

retrieve_trust_chain() {
  section_header "Retrieve the Chain of Trust"

  login || { pause; return 0; }
  api_call GET "/trustchain" "" "Retrieving chain of trust"
  print_response
  pause
  return 0
}

# =========================
# Certificate checks
# =========================

check_validation_policy() {
  section_header "Checking Certificates :: Validation Policy"
  login || { pause; return 1; }
  api_call GET "/validationpolicy"
  print_response
  pause
}

check_certs_issued_count() {
  section_header "Checking Certificates :: Issued Certificate Counter"
  login || { pause; return 1; }
  api_call GET "/counters/certificates/issued"
  print_response
  pause
}

check_certs_revoked_count() {
  section_header "Checking Certificates :: Revoked Certificate Counter"
  login || { pause; return 1; }
  api_call GET "/counters/certificates/revoked"
  print_response
  pause
}

check_issued_list() {
  section_header "Checking Certificates :: Issued Certificates"
  login || { pause; return 1; }
  local NOW FROM
  NOW="$(date +%s)"
  FROM="$((NOW - 2592000))" # 30 days ago
  api_call GET "/stats/issued?page=1&per_page=100&from=$FROM&to=$NOW"
  print_response
  pause
}

check_revoked_list() {
  section_header "Checking Certificates :: Revoked Certificates"
  login || { pause; return 1; }
  local NOW FROM
  NOW="$(date +%s)"
  FROM="$((NOW - 2592000))" 
  api_call GET "/stats/revoked?page=1&per_page=100&from=$FROM&to=$NOW"
  print_response
  pause
}

check_expiring_list() {
  section_header "Checking Certificates :: Expiring Certificates"
  login || { pause; return 1; }
  local NOW FROM
  NOW="$(date +%s)"
  FROM="$((NOW - 2592000))"
  api_call GET "/stats/expiring?page=1&per_page=100&from=$FROM&to=$NOW"
  print_response
  pause
}

check_issuance_quota() {
  section_header "Checking Certificates :: Issuance Quota"
  login || { pause; return 1; }
  api_call GET "/quotas/issuance"
  print_response
  pause
}

# =========================
# Domain claims
# =========================

claim_domain() {
  section_header "Claim a Domain"
  local domain
  read -r -p "Enter domain to claim: " domain

  if [[ -z "$domain" ]]; then
    echo "Domain is required." >&2
    pause
    return 1
  fi

  login || { pause; return 1; }
  api_call POST "/claims/domains/$domain"
  print_response
  pause
}

retrieve_domain_claim() {
  section_header "Retrieve a Domain Claim"
  local claim_id
  claim_id="$(read_claim_id)" || { pause; return 1; }
  login || { pause; return 1; }
  api_call GET "/claims/domains/$claim_id"
  print_response
  pause
}

delete_domain_claim() {
  section_header "Delete a Domain Claim"
  local claim_id
  claim_id="$(read_claim_id)" || { pause; return 1; }
  login || { pause; return 1; }
  api_call DELETE "/claims/domains/$claim_id"
  print_response
  pause
}

retrieve_adns() {
  section_header "Retrieve ADNs"
  local claim_id
  claim_id="$(read_claim_id)" || { pause; return 1; }
  login || { pause; return 1; }
  api_call GET "/claims/domains/$claim_id/dns"
  print_response
  pause
}

confirm_domain_dns() {
  section_header "Confirm Domain Control via DNS"
  local claim_id auth_domain payload
  claim_id="$(read_claim_id)" || { pause; return 1; }
  read -r -p "Enter authorization_domain (leave blank if not needed): " auth_domain

  if [[ -n "$auth_domain" ]]; then
    payload="$(jq -nc --arg authorization_domain "$auth_domain" '{authorization_domain:$authorization_domain}')"
  else
    payload=""
  fi

  login || { pause; return 1; }
  api_call POST "/claims/domains/$claim_id/dns" "$payload"

  echo
  if [[ "$HTTP_CODE" == "201" ]]; then
    echo "DNS assertion request created. Atlas is still checking."
  elif [[ "$HTTP_CODE" == "204" ]]; then
    echo "DNS validation completed successfully."
  fi
  print_response
  pause
}

confirm_domain_http() {
  section_header "Confirm Domain Control via HTTP"
  local claim_id auth_domain scheme payload
  claim_id="$(read_claim_id)" || { pause; return 1; }
  read -r -p "Enter authorization_domain: " auth_domain
  read -r -p "Enter scheme [http|https]: " scheme

  if [[ -z "$auth_domain" || -z "$scheme" ]]; then
    echo "Both authorization_domain and scheme are required." >&2
    pause
    return 1
  fi

  payload="$(
    jq -nc \
      --arg authorization_domain "$auth_domain" \
      --arg scheme "$scheme" \
      '{authorization_domain:$authorization_domain, scheme:$scheme}'
  )"

  login || { pause; return 1; }
  api_call POST "/claims/domains/$claim_id/http" "$payload"

  echo
  if [[ "$HTTP_CODE" == "201" ]]; then
    echo "HTTP assertion request created. Atlas is still checking."
  elif [[ "$HTTP_CODE" == "204" ]]; then
    echo "HTTP validation completed successfully."
  fi
  print_response
  pause
}

view_authorized_email_addresses() {
  section_header "Authorized Email Addresses"
  local claim_id
  claim_id="$(read_claim_id)" || { pause; return 1; }
  login || { pause; return 1; }
  api_call GET "/claims/domains/$claim_id/email"
  print_response
  pause
}

confirm_domain_email() {
  section_header "Confirm Domain Control via Email"
  local claim_id email_address payload
  claim_id="$(read_claim_id)" || { pause; return 1; }
  read -r -p "Enter approval email address: " email_address

  if [[ -z "$email_address" ]]; then
    echo "Email address is required." >&2
    pause
    return 1
  fi

  payload="$(
    jq -nc \
      --arg email_address "$email_address" \
      '{email_address:$email_address}'
  )"

  login || { pause; return 1; }
  api_call POST "/claims/domains/$claim_id/email" "$payload"

  echo
  if [[ "$HTTP_CODE" == "201" ]]; then
    echo "Validation email request created. Check the inbox and click the approval link."
  elif [[ "$HTTP_CODE" == "204" ]]; then
    echo "Email validation completed successfully."
  fi
  print_response
  pause
}

reassert_domain_claim() {
  section_header "Reassert a Domain Claim"
  local claim_id
  claim_id="$(read_claim_id)" || { pause; return 1; }
  login || { pause; return 1; }
  api_call POST "/claims/domains/$claim_id/reassert"

  print_response

  local location
  location="$(awk 'BEGIN{IGNORECASE=1} /^Location:/ {print $2}' "$RESP_HEADERS" | tr -d '\r' | tail -n 1)"
  if [[ -n "$location" ]]; then
    echo "Location header: $location"
  fi
  pause
}

list_domain_claims() {
  section_header "List Domain Claims"
  login || { pause; return 1; }
  api_call GET "/claims/domains"
  print_response
  pause
}

# =========================
# IP claims
# =========================

list_ip_claims() {
  section_header "List IP Address Claims"
  login || { pause; return 1; }
  api_call GET "$IP_CLAIMS_BASE"
  print_response
  pause
}

claim_ip_address() {
  section_header "Claim an IP Address"
  local ip_address
  read -r -p "Enter IPv4 or IPv6 address to claim: " ip_address

  if [[ -z "$ip_address" ]]; then
    echo "IP address is required." >&2
    pause
    return 1
  fi

  login || { pause; return 1; }
  api_call POST "$IP_CLAIMS_BASE/$ip_address"
  print_response
  pause
}

retrieve_ip_claim() {
  section_header "Retrieve an IP Address Claim"
  local claim_id
  claim_id="$(read_claim_id)" || { pause; return 1; }
  login || { pause; return 1; }
  api_call GET "$IP_CLAIMS_BASE/$claim_id"
  print_response
  pause
}

delete_ip_claim() {
  section_header "Delete an IP Address Claim"
  local claim_id
  claim_id="$(read_claim_id)" || { pause; return 1; }
  login || { pause; return 1; }
  api_call DELETE "$IP_CLAIMS_BASE/$claim_id"
  print_response
  pause
}

confirm_ip_http() {
  section_header "Confirm IP Control via HTTP"
  local claim_id authorization_ip_address payload scheme
  claim_id="$(read_claim_id)" || { pause; return 1; }
  read -r -p "Enter authorization IP address: " authorization_ip_address
  read -r -p "Enter scheme [http|https]: " scheme

  if [[ -z "$authorization_ip_address" ]]; then
    echo "authorization_ip_address is required." >&2
    pause
    return 1
  fi

  if [[ -z "$scheme" ]]; then
    echo "Scheme is required." >&2
    pause
    return 1
  fi

  payload="$(
    jq -nc \
      --arg authorization_ip_address "$authorization_ip_address" \
      --arg scheme "$scheme" \
      '{authorization_ip_address:$authorization_ip_address, scheme:$scheme}'
  )"

  login || { pause; return 1; }
  api_call POST "$IP_CLAIMS_BASE/$claim_id/http" "$payload"

  echo
  if [[ "$HTTP_CODE" == "201" ]]; then
    echo "HTTP assertion request created. Atlas is still checking."
  elif [[ "$HTTP_CODE" == "204" ]]; then
    echo "HTTP validation completed successfully."
  fi
  print_response
  pause
}

reassert_ip_claim() {
  section_header "Reassert an IP Address Claim"
  local claim_id
  claim_id="$(read_claim_id)" || { pause; return 1; }
  login || { pause; return 1; }
  api_call POST "$IP_CLAIMS_BASE/$claim_id/reassert"
  print_response

  local location
  location="$(awk 'BEGIN{IGNORECASE=1} /^Location:/ {print $2}' "$RESP_HEADERS" | tr -d '\r' | tail -n 1)"
  if [[ -n "$location" ]]; then
    echo "Location header: $location"
  fi
  pause
}

# =========================
# Menus
# =========================

show_main_menu() {
  section_header "Main Menu"
  cat <<'EOF'
1) Issue certificates
2) Check certificates
3) Claim domain
4) Claim IP
5) Exit
EOF
  echo
}

show_issuance_menu() {
  section_header "Issue Certificates"
  cat <<'EOF'
1) Auto issuance
2) Request a new certificate
3) Get certificate by ID
4) Revoke certificate by ID
5) Rekey certificate (Reissue)
6) Retrieve the chain of trust
7) Back to main menu
EOF
  echo
}

show_checking_menu() {
  section_header "Check Certificates"
  cat <<'EOF'
1) Retrieve the validation policy
2) Retrieve the number of certificates issued
3) Retrieve the number of certificates revoked
4) Retrieve a list of issued certificates
5) Retrieve a list of revoked certificates
6) Retrieve a list of expiring certificates
7) Retrieve the certificate issuance quota
8) Back to main menu
EOF
  echo
}

show_domain_menu() {
  section_header "Claim Domain"
  cat <<'EOF'
1) Claim a domain
2) Retrieve a domain claim
3) Delete a domain claim
4) Retrieve a list of Authorization Domain Names (ADNs)
5) Confirm control of a domain using DNS validation method
6) Confirm control of a domain using HTTP validation method
7) View a list of email addresses authorized to perform the Email validation method
8) Confirm control of a domain using Email validation method
9) Reassert a domain claim
10) Retrieve a list of domain claims
11) Back to main menu
EOF
  echo
}

show_ip_menu() {
  section_header "Claim IP"
  cat <<'EOF'
1) Retrieve a list of IP address claims
2) Claim an IP address
3) Retrieve an IP address claim
4) Delete an IP address claim
5) Confirm control of an IPv4 or IPv6 address using HTTP validation method
6) Reassert an IP address claim
7) Back to main menu
EOF
  echo
}

issuance_menu() {
  while true; do
    show_issuance_menu
    read -r -p "Select an option [1-7]: " choice

    case "$choice" in
      1) auto_issuance || true ;;
      2) request_new_certificate || true ;;
      3) get_certificate_by_id || true ;;
      4) revoke_certificate_by_id || true ;;
      5) rekey_certificate || true ;;
      6) retrieve_trust_chain || true ;;
      7) return 0 ;;
      *) echo "Invalid selection. Try again." ; sleep 1 ;;
    esac
  done
}

checking_menu() {
  while true; do
    show_checking_menu
    read -r -p "Select an option [1-8]: " choice
    case "$choice" in
      1) check_validation_policy ;;
      2) check_certs_issued_count ;;
      3) check_certs_revoked_count ;;
      4) check_issued_list ;;
      5) check_revoked_list ;;
      6) check_expiring_list ;;
      7) check_issuance_quota ;;
      8) return 0 ;;
      *) echo "Invalid selection. Try again." ; sleep 1 ;;
    esac
  done
}

domain_menu() {
  while true; do
    show_domain_menu
    read -r -p "Select an option [1-11]: " choice
    case "$choice" in
      1) claim_domain ;;
      2) retrieve_domain_claim ;;
      3) delete_domain_claim ;;
      4) retrieve_adns ;;
      5) confirm_domain_dns ;;
      6) confirm_domain_http ;;
      7) view_authorized_email_addresses ;;
      8) confirm_domain_email ;;
      9) reassert_domain_claim ;;
      10) list_domain_claims ;;
      11) return 0 ;;
      *) echo "Invalid selection. Try again." ; sleep 1 ;;
    esac
  done
}

ip_menu() {
  while true; do
    show_ip_menu
    read -r -p "Select an option [1-7]: " choice
    case "$choice" in
      1) list_ip_claims ;;
      2) claim_ip_address ;;
      3) retrieve_ip_claim ;;
      4) delete_ip_claim ;;
      5) confirm_ip_http ;;
      6) reassert_ip_claim ;;
      7) return 0 ;;
      *) echo "Invalid selection. Try again." ; sleep 1 ;;
    esac
  done
}

main() {
  ensure_config
  welcome

  while true; do
    show_main_menu
    read -r -p "Select an option [1-5]: " choice

    case "$choice" in
      1) issuance_menu || true ;;
      2) checking_menu || true ;;
      3) domain_menu || true ;;
      4) ip_menu || true ;;
      5) goodbye; exit 0 ;;
      *) echo "Invalid selection. Try again." ; sleep 1 ;;
    esac
  done
}

main "$@"
