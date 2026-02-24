# Lambda Compare

Compare Lambda functions between AWS accounts to verify migration.

## Installation

```bash
cd pytools/lambdacompare
uv pip install -e .
```

Or with pip:

```bash
cd pytools/lambdacompare
pip install -e .
```

After installation, you can run the tool as a module:

```bash
python -m lambdacompare.compare_lambda_migration --help
```

## Usage

Run the tool as a Python module:

```bash
python -m lambdacompare.compare_lambda_migration \
  --old-account 123456789012 \
  --new-account 987654321098 \
  --old-profile old-account-admin \
  --new-profile new-account-admin \
  --prefix dev \
  --output results.json
```

### Arguments

- `--old-account`: Old AWS account ID (required)
- `--new-account`: New AWS account ID (required)
- `--old-profile`: AWS profile for old account (required)
- `--new-profile`: AWS profile for new account (required)
- `--old-region`: Region for old account (default: eu-west-2)
- `--new-region`: Region for new account (default: eu-west-2)
- `--prefix`: Prefix for functions in both accounts (e.g., "dev", "authdev1")
- `--all`: Compare all Lambda functions instead of just the target list
- `--output`: Output file for results (JSON)

## Comparison Modes

### Target Functions Mode (Default)
By default, the script compares only specific Lambda functions:
- mfa-methods-update-lambda
- mfa-methods-delete-lambda
- mfa-methods-create-lambda
- mfa-methods-retrieve-lambda
- update-phone-number-lambda
- update-password-lambda
- update-email-lambda
- send-otp-notification-lambda
- delete-account-lambda
- authenticate-lambda
- api_gateway_authorizer
- bulk-remove-account-lambda
- manually-delete-account-lambda
- account-management-sqs-lambda

### All Functions Mode
Use `--all` flag to compare all Lambda functions in both accounts.

## Examples

### Compare target functions with prefix

```bash
python -m lambdacompare.compare_lambda_migration \
  --old-account 761723964695 \
  --new-account 058264536367 \
  --old-profile gds-di-development-ApprovedAdmin \
  --new-profile di-authentication-build-ApprovedAdmin \
  --prefix build \
  --output results.json
```

### Compare ALL functions with prefix

```bash
python -m lambdacompare.compare_lambda_migration \
  --old-account 761723964695 \
  --new-account 058264536367 \
  --old-profile gds-di-development-ApprovedAdmin \
  --new-profile di-authentication-build-ApprovedAdmin \
  --prefix build \
  --all \
  --output results.json
```

### Compare target functions without prefix

```bash
python -m lambdacompare.compare_lambda_migration \
  --old-account 123456789012 \
  --new-account 987654321098 \
  --old-profile old-account-admin \
  --new-profile new-account-admin \
  --output results.json
```

## Features

- Compares Lambda function configurations (runtime, handler, memory, timeout, etc.)
- Compares environment variables
- Parallel fetching for better performance
- Reuses AWS sessions to avoid multiple SSO login prompts
- Supports prefix filtering for sub-account resources
- Outputs detailed comparison results in JSON format
- Generates interactive HTML reports automatically
- Two comparison modes: target functions only or all functions

## Output

The script provides:
- Console output with color-coded status (✅ PASS, ⚠️ REVIEW)
- Target function list display (when not using --all)
- Detailed differences for configuration and environment variables
- Summary statistics
- JSON output file with complete comparison data
- Interactive HTML report (lambda-comparison-report-{prefix}.html)
