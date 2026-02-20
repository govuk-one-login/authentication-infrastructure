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
  --filter account-management \
  --output results.json
```

### Arguments

- `--old-account`: Old AWS account ID (required)
- `--new-account`: New AWS account ID (required)
- `--old-profile`: AWS profile for old account (required)
- `--new-profile`: AWS profile for new account (required)
- `--old-region`: Region for old account (default: eu-west-2)
- `--new-region`: Region for new account (default: eu-west-2)
- `--prefix`: Prefix for functions in both accounts (e.g., "dev", "authdev1"). If not specified, all functions are compared
- `--filter`: Additional filter string for functions (e.g., "account-management")
- `--output`: Output file for results (JSON)

## Examples

### Compare all dev-* functions between accounts

```bash
python -m lambdacompare.compare_lambda_migration \
  --old-account 123456789012 \
  --new-account 987654321098 \
  --old-profile old-account-admin \
  --new-profile new-account-admin \
  --prefix dev
```

### Compare only authdev1-* account-management functions

```bash
python -m lambdacompare.compare_lambda_migration \
  --old-account 123456789012 \
  --new-account 987654321098 \
  --old-profile old-account-admin \
  --new-profile new-account-admin \
  --prefix authdev1 \
  --filter account-management
```

### Compare all functions (no prefix filter)

```bash
python -m lambdacompare.compare_lambda_migration \
  --old-account 123456789012 \
  --new-account 987654321098 \
  --old-profile old-account-admin \
  --new-profile new-account-admin
```

## Features

- Compares Lambda function configurations (runtime, handler, memory, timeout, etc.)
- Compares environment variables
- Compares IAM role policies (managed and inline)
- Parallel fetching for better performance
- Reuses AWS sessions to avoid multiple SSO login prompts
- Supports prefix filtering for sub-account resources
- Outputs detailed comparison results in JSON format

## Output

The script provides:
- Console output with color-coded status (✅ PASS, ⚠️ REVIEW)
- Detailed differences for configuration, environment variables, and policies
- Summary statistics
- Optional JSON output file with complete comparison data
