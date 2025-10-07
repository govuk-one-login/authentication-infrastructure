#!/bin/bash

if [ $# -lt 3 ] || [ $# -gt 4 ]; then
  echo "Usage: $0 <acc1> <acc2> <env> [lambda-suffix]"
  echo "Example: $0 acc1 acc2 dev"
  echo "Example: $0 acc1 acc2 dev auth-code"
  echo "If lambda-suffix is not provided, all functions matching env will be compared"
  exit 1
fi

ACC1=$1
ACC2=$2
ENV=$3
LAMBDA_SUFFIX=$5

DIFFCMD="diff"
if command -v colordiff > /dev/null 2>&1; then
  DIFFCMD="colordiff"
fi

AWS_REGION="eu-west-2"

acc_login() {
  echo "====== Using: ${AWS_ACCOUNT} - ${AWS_PROFILE} - ${AWS_REGION} ======"

  if ! aws sts get-caller-identity &> /dev/null; then
    aws sso login --profile "${AWS_PROFILE}"
  fi
}

# get_lambda_functions <acc> <env>
get_lambda_functions() {
  local acc=$1
  local env=$2

  export AWS_ACCOUNT="${acc}"
  export AWS_PROFILE="${AWS_ACCOUNT}-admin"

  acc_login >&2

  aws lambda list-functions \
    --region "${AWS_REGION}" \
    --query "Functions[?starts_with(FunctionName, '${env}-')].FunctionName" \
    --output text | tr '\t' '\n' | sed "s/^${env}-//" | sed 's/-lambda$//'
}

# get_lambda_configs_for_functions <acc> <env> <output_dir> <functions_file>
get_lambda_configs_for_functions() {
  local acc=$1
  local env=$2
  local output_dir=$3
  local functions_file=$4

  export AWS_ACCOUNT="${acc}"
  export AWS_PROFILE="${AWS_ACCOUNT}-admin"

  acc_login >&2

  while read -r suffix; do
    local function_name="${env}-${suffix}-lambda"
    local config_file="${output_dir}/${acc}-${suffix}.json"

    echo "Getting config for ${function_name} (${AWS_ACCOUNT}) ..."

    # Get function configuration and provisioned concurrency
    {
      # Get basic configuration
      FUNC_CONFIG=$(aws lambda get-function-configuration \
        --function-name "${function_name}" \
        --region "${AWS_REGION}" \
        --query '{
                Runtime: Runtime,
                MemorySize: MemorySize,
                Timeout: Timeout,
                Handler: Handler,
                Environment: Environment.Variables,
                DeadLetterConfig: DeadLetterConfig,
                PackageType: PackageType,
                Architectures: Architectures,
                SnapStart: SnapStart
            }' \
        --output json 2> /dev/null)

      # Get provisioned concurrency
      PROV_CONCURRENCY=$(aws lambda get-provisioned-concurrency-config \
        --function-name "${function_name}" \
        --region "${AWS_REGION}" \
        --query '{AllocatedConcurrency: AllocatedConcurrency, AvailableConcurrency: AvailableConcurrency, Status: Status}' \
        --output json 2> /dev/null || echo '{"AllocatedConcurrency": null, "AvailableConcurrency": null, "Status": "Not configured"}')

      # Get function URL
      FUNC_URL=$(aws lambda get-function-url-config \
        --function-name "${function_name}" \
        --region "${AWS_REGION}" \
        --query '{FunctionUrl: FunctionUrl, AuthType: AuthType, Cors: Cors}' \
        --output json 2> /dev/null || echo '{"FunctionUrl": null, "AuthType": null, "Cors": null}')

      # Combine all configurations
      echo "${FUNC_CONFIG}" | jq --argjson pc "${PROV_CONCURRENCY}" --argjson fu "${FUNC_URL}" '. + {ProvisionedConcurrency: $pc, FunctionUrl: $fu}'
    } > "${config_file}"
  done < "${functions_file}"
}

compare_single_lambda() {
  local TEMP_DIR=$1

  # Create a temp file with just the single function
  SINGLE_FUNCTION_FILE="${TEMP_DIR}/single_function.txt"
  echo "${LAMBDA_SUFFIX}" > "${SINGLE_FUNCTION_FILE}"

  CONFIG1="${TEMP_DIR}/${ACC1}-${LAMBDA_SUFFIX}.json"
  CONFIG2="${TEMP_DIR}/${ACC2}-${LAMBDA_SUFFIX}.json"

  echo "Getting configurations in parallel..."
  get_lambda_configs_for_functions "${ACC1}" "${ENV}" "${TEMP_DIR}" "${SINGLE_FUNCTION_FILE}" &
  get_lambda_configs_for_functions "${ACC2}" "${ENV}" "${TEMP_DIR}" "${SINGLE_FUNCTION_FILE}" &
  wait

  echo "=== Lambda Configuration Comparison ==="
  echo "Lambda: ${ENV}-${LAMBDA_SUFFIX}-lambda"
  echo "Accounts: ${ACC1} vs ${ACC2}"
  echo ""

  ${DIFFCMD} -u "${CONFIG1}" "${CONFIG2}"
  EXITCODE=$?

  if [ ${EXITCODE} -ne 0 ]; then
    echo "======= CONFIGS ARE DIFFERENT ======="
  else
    echo "======= CONFIGS MATCH ======="
  fi

  return ${EXITCODE}
}

compare_accounts() {
  local TEMP_DIR=$1
  local EXITCODE=0

  # Get function lists first (lightweight calls)
  ACC1_FUNCTIONS_FILE="${TEMP_DIR}/${ACC1}_functions.txt"
  ACC2_FUNCTIONS_FILE="${TEMP_DIR}/${ACC2}_functions.txt"
  ACC1_ONLY_FILE="${TEMP_DIR}/${ACC1}_only.txt"
  ACC2_ONLY_FILE="${TEMP_DIR}/${ACC2}_only.txt"
  COMMON_FUNCTIONS_FILE="${TEMP_DIR}/common_functions.txt"

  echo "Getting Lambda function lists..."
  get_lambda_functions "${ACC1}" "${ENV}" | sort > "${ACC1_FUNCTIONS_FILE}" &
  get_lambda_functions "${ACC2}" "${ENV}" | sort > "${ACC2_FUNCTIONS_FILE}" &
  wait

  # Create comparison files
  comm -23 "${ACC1_FUNCTIONS_FILE}" "${ACC2_FUNCTIONS_FILE}" > "${ACC1_ONLY_FILE}"
  comm -13 "${ACC1_FUNCTIONS_FILE}" "${ACC2_FUNCTIONS_FILE}" > "${ACC2_ONLY_FILE}"
  comm -12 "${ACC1_FUNCTIONS_FILE}" "${ACC2_FUNCTIONS_FILE}" > "${COMMON_FUNCTIONS_FILE}"

  # Display results
  echo "=== Function List Comparison ==="
  echo "Functions in ${ACC1} only ($(wc -l < "${ACC1_ONLY_FILE}")):"
  cat "${ACC1_ONLY_FILE}"
  echo ""
  echo "Functions in ${ACC2} only ($(wc -l < "${ACC2_ONLY_FILE}")):"
  cat "${ACC2_ONLY_FILE}"
  echo ""
  echo "Common functions ($(wc -l < "${COMMON_FUNCTIONS_FILE}")):"
  cat "${COMMON_FUNCTIONS_FILE}"
  echo ""

  # Check if there are differences
  if [ -s "${ACC1_ONLY_FILE}" ] || [ -s "${ACC2_ONLY_FILE}" ]; then
    echo "WARNING: Function lists don't match between accounts"
  fi

  # Only get configs for common functions
  TOTAL=$(wc -l < "${COMMON_FUNCTIONS_FILE}")
  if [ "${TOTAL}" -eq 0 ]; then
    echo "No common functions to compare"
    rm -rf "${TEMP_DIR}"
    exit 0
  fi

  echo "Getting configurations for ${TOTAL} common functions from both accounts in parallel..."
  get_lambda_configs_for_functions "${ACC1}" "${ENV}" "${TEMP_DIR}" "${COMMON_FUNCTIONS_FILE}" &
  get_lambda_configs_for_functions "${ACC2}" "${ENV}" "${TEMP_DIR}" "${COMMON_FUNCTIONS_FILE}" &
  wait

  echo "Comparing configurations for common functions..."
  echo ""

  # Compare all the generated configs
  COUNTER=0

  while read -r suffix; do
    COUNTER=$((COUNTER + 1))
    echo "=== Comparing ${suffix} (${COUNTER}/${TOTAL}) ==="
    CONFIG1="${TEMP_DIR}/${ACC1}-${suffix}.json"
    CONFIG2="${TEMP_DIR}/${ACC2}-${suffix}.json"

    ${DIFFCMD} -u "${CONFIG1}" "${CONFIG2}"
    EXITCODE=$?

    if [ ${EXITCODE} -ne 0 ]; then
      echo "DIFFERENT: ${suffix}"
      EXITCODE=1
    else
      echo "MATCH: ${suffix}"
    fi
    echo ""
  done < "${COMMON_FUNCTIONS_FILE}"

  rm -rf "${TEMP_DIR}"

  if [ ${EXITCODE} -ne 0 ]; then
    echo "======= SOME CONFIGS ARE DIFFERENT ======="
  else
    echo "======= ALL CONFIGS MATCH ======="
  fi

  return ${EXITCODE}
}

main() {
  TEMP_DIR=$(mktemp -d)
  echo "====== TEMPDIR: ${TEMP_DIR} ======"

  EXITCODE=0
  if [ -z "${LAMBDA_SUFFIX}" ]; then
    compare_accounts "${TEMP_DIR}"
    EXITCODE=$?
  else
    compare_single_lambda "${TEMP_DIR}"
    EXITCODE=$?
  fi

  rm -rf "${TEMP_DIR}"
  exit ${EXITCODE}
}

########
main
