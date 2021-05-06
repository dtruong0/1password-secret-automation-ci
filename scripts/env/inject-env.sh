#!/usr/bin/env bash
set -a
PATH=$(pwd)/node_modules/.bin:"${PATH}"

: "${ENV?" Variable ENV not set"}"
NO_SECRETS=${NO_SECRETS:=false}

print_red() {
  RED='\033[0;31m'
  NC='\033[0m' # No Color
  echo -e "${RED}${1}${NC}"
}

local_secrets() {
  SECRET_DOC=$1
  SECRET_TYPE=$2
  : "${OP_VAULT?"[ENV ERROR] Variable OP_VAULT not set"}"
  : "${SECRET_DOC?"[ENV ERROR] Variable SECRET_DOC not set"}"
  : "${SECRET_TYPE?"[ENV ERROR] Variable SECRET_TYPE not set"}"
  # Check op creds
  ACCOUNT=$(op get account 2>/dev/null)
  if [ -z "${ACCOUNT}" ]; then
    print_red '[ENV ERROR] Sign into one password cli first: eval "$(op signin orchestrated)"'
    exit 1
  fi

  echo "[ENV] loading secrets from ${OP_VAULT} ${SECRET_TYPE} : ${SECRET_DOC}"
  #  Export in a format that prevents bash injection
  CLI_SECRETS="$(op get item --vault "${OP_VAULT}" "${SECRET_DOC}" |
    jq -r '.details.sections[].fields[]? | ("export " + "@SINGLE_QUOTE@"  + .t + "@SINGLE_QUOTE@"  + "=" + "@SINGLE_QUOTE@"  + .v + "@SINGLE_QUOTE@" )' |
    sed "s#'#'\"'\"'#g" | sed "s#@SINGLE_QUOTE@#'#g")"
  if [ "$CLI_SECRETS" = "" ]; then
    print_red "[ENV ERROR] one password vault or document not found or empty, ${OP_VAULT} ${SECRET_TYPE} : ${SECRET_DOC}"
    exit 1
  fi
  eval "${CLI_SECRETS}"
}

ci_secrets() {
  : "${OP_VAULT?"[ENV ERROR] Variable OP_VAULT not set"}"
  : "${OP_AUTOMATION_CREDENTIALS?"[ENV ERROR] Variable OP_AUTOMATION_CREDENTIALS not set"}"
  : "${OP_TOKEN?"[ENV ERROR] Variable OP_TOKEN not set"}"

  # Add secrets from docker logs to shell
  docker-compose -f ./scripts/env/docker-compose.yml down --remove-orphans &>/dev/null
  docker-compose -f ./scripts/env/docker-compose.yml up --build -d
  echo "[ENV] loading secrets from ${OP_SHARED_DOCUMENT} & ${OP_TENANT_DOCUMENT}"
  CI_SECRETS=""
  for i in {1..60}; do
    sleep 5
    CI_SECRETS="$(docker logs "$(docker ps -a | grep node-12 | awk '{print $1}')")"
    if [ "$CI_SECRETS" != "" ]; then break; fi
    if [ "$i" = "60" ]; then print_red "[ENV ERROR] failed to pull secrets" && exit 1; fi
    echo "[ENV] Waiting for secrets automation #${i}"
  done
  eval "${CI_SECRETS}"
  # Clean up
  docker-compose -f ./scripts/env/docker-compose.yml down --remove-orphans &>/dev/null || true
}


echo "[ENV] Injecting enviroment varibles with ${0} 💪"
# Check .env file
ENV_FILE=env/.env."${ENV}"
if [[ ! -f ${ENV_FILE} ]]; then
  print_red "[ENV ERROR] Environment file \"${ENV_FILE}\" does not exist aborting.'" && exit 1
fi
source "${ENV_FILE}"
if [[ -n "$SHARED_ENV_FILE" ]] && [[ ! -f ${SHARED_ENV_FILE} ]]; then
  print_red "[ENV ERROR] Environment file \"${SHARED_ENV_FILE}\" does not exist aborting.'" && exit 1
fi
# Write and load .env file
echo "# This config file is auto generated." >.env
{
  cat "${SHARED_ENV_FILE}"
  echo ""
  cat "${ENV_FILE}"
} >>.env
source .env
echo "[ENV] Loaded Shared Env File: ${SHARED_ENV_FILE}"
echo "[ENV] Loaded Tenant Env File: ${ENV_FILE}"

# Load secrets
if [ "$NO_SECRETS" = "true" ]; then
  echo "[ENV] NO_SECRETS=true"
elif [ "$CI" != "true" ]; then
  echo "[ENV] Loading secrets from CLI"
  [[ -n $OP_SHARED_DOCUMENT ]] && local_secrets "${OP_SHARED_DOCUMENT}" "OP_SHARED_DOCUMENT"
  [[ -n $OP_TENANT_DOCUMENT ]] && local_secrets "${OP_TENANT_DOCUMENT}" "OP_TENANT_DOCUMENT"
else
  echo "[ENV] Loading secrets from Secrets Automation"
  ci_secrets
fi

echo "[ENV] Running command:" "$@"
eval "$@"
