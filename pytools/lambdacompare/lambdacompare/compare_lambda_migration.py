#!/usr/bin/env python3
"""Compare Lambda functions between old and new AWS accounts to verify migration."""
import boto3
import argparse
import json
import sys
from typing import Dict, List, Any
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed


def get_session(profile: str):
    """Get boto3 session for specified profile and test authentication."""
    try:
        session = boto3.Session(profile_name=profile)
        # Test the session with a simple STS call
        sts = session.client("sts")
        sts.get_caller_identity()
        return session
    except Exception as e:
        if "Token has expired" in str(e) or "sso" in str(e).lower():
            print(f"SSO token expired for profile {profile}.")
            print(f"Please run: aws sso login --profile {profile}")
            sys.exit(1)
        else:
            raise e


def get_lambda_client(session: boto3.Session, region: str):
    """Get Lambda client from session."""
    return session.client("lambda", region_name=region)


def get_function_details(lambda_client, func_name: str) -> Dict:
    """Get detailed configuration for a single Lambda function."""
    try:
        config = lambda_client.get_function(FunctionName=func_name)
        func_config = config["Configuration"]
        return {
            "name": func_name,
            "config": func_config,
            "env_vars": func_config.get("Environment", {}).get("Variables", {}),
            "role_arn": func_config["Role"],
        }
    except Exception as e:
        print(f"Error getting details for {func_name}: {e}")
        return None


def list_lambdas(lambda_client, max_workers: int = 10) -> Dict[str, Dict]:
    """List all Lambda functions and their configurations in parallel."""
    # First, get list of all function names
    function_names = []
    paginator = lambda_client.get_paginator("list_functions")
    for page in paginator.paginate():
        for func in page["Functions"]:
            function_names.append(func["FunctionName"])

    print(f"  Found {len(function_names)} functions, fetching details...")

    # Fetch details in parallel
    functions = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all tasks
        future_to_name = {
            executor.submit(get_function_details, lambda_client, name): name
            for name in function_names
        }

        # Collect results
        for future in as_completed(future_to_name):
            result = future.result()
            if result:
                functions[result["name"]] = {
                    "config": result["config"],
                    "env_vars": result["env_vars"],
                    "role_arn": result["role_arn"],
                }

    return functions





def find_matching_functions(
    old_functions: Dict,
    new_functions: Dict,
    prefix: str = None,
    compare_all: bool = False,
) -> Dict[str, str]:
    """Find matching functions between accounts."""
    # Specific Lambda functions to compare
    target_functions = [
        "mfa-methods-update-lambda",
        "mfa-methods-delete-lambda",
        "mfa-methods-create-lambda",
        "mfa-methods-retrieve-lambda",
        "update-phone-number-lambda",
        "update-password-lambda",
        "update-email-lambda",
        "send-otp-notification-lambda",
        "delete-account-lambda",
        "authenticate-lambda",
        "api_gateway_authorizer",
        "bulk-remove-account-lambda",
        "manually-delete-account-lambda",
        "account-management-sqs-lambda"
    ]

    if not compare_all:
        print("\n📋 Target Lambda functions to compare:")
        for func in target_functions:
            expected_name = f"{prefix}-{func}" if prefix else func
            print(f"  - {expected_name}")
        print()

    matches = {}

    if compare_all:
        # Compare all functions with prefix matching
        if prefix:
            prefix_lower = f"{prefix.lower()}-"
            filtered_old = {
                name: func for name, func in old_functions.items()
                if name.lower().startswith(prefix_lower)
            }
            filtered_new = {
                name: func for name, func in new_functions.items()
                if name.lower().startswith(prefix_lower)
            }
        else:
            filtered_old = old_functions
            filtered_new = new_functions

        # Simple name matching for all functions
        for new_name in filtered_new.keys():
            if new_name in filtered_old:
                matches[new_name] = new_name
                print(f"  Matched: {new_name}")
            else:
                print(f"  Missing in old account: {new_name}")

        for old_name in filtered_old.keys():
            if old_name not in filtered_new:
                print(f"  Missing in new account: {old_name}")
    else:
        # Compare only target functions
        for target in target_functions:
            old_match = None
            new_match = None

            # Find in old account (with or without prefix)
            for old_name in old_functions.keys():
                if prefix:
                    expected_old_name = f"{prefix}-{target}"
                    if old_name.lower() == expected_old_name.lower():
                        old_match = old_name
                        break
                else:
                    if old_name.lower() == target.lower():
                        old_match = old_name
                        break

            # Find in new account (with or without prefix)
            for new_name in new_functions.keys():
                if prefix:
                    expected_new_name = f"{prefix}-{target}"
                    if new_name.lower() == expected_new_name.lower():
                        new_match = new_name
                        break
                else:
                    if new_name.lower() == target.lower():
                        new_match = new_name
                        break

            # Report results
            if old_match and new_match:
                matches[new_match] = old_match
                print(f"  Matched: {old_match} -> {new_match}")
            elif old_match and not new_match:
                print(f"  Missing in new account: {target} (found as {old_match} in old)")
            elif new_match and not old_match:
                print(f"  Missing in old account: {target} (found as {new_match} in new)")
            else:
                print(f"  Not found in either account: {target}")

    print(f"\n  Total matches found: {len(matches)}")
    return matches


def compare_env_vars(old_env: Dict, new_env: Dict) -> Dict[str, Any]:
    """Compare environment variables between functions."""
    differences = {
        "missing_in_new": [],
        "missing_in_old": [],
        "different_values": [],
    }

    for key, value in old_env.items():
        if key not in new_env:
            differences["missing_in_new"].append(key)
        elif new_env[key] != value:
            differences["different_values"].append(
                {"key": key, "old_value": value, "new_value": new_env[key]}
            )

    for key in new_env.keys():
        if key not in old_env:
            differences["missing_in_old"].append(key)

    return differences


def compare_function_config(old_config: Dict, new_config: Dict) -> Dict[str, Any]:
    """Compare Lambda function configurations."""
    important_fields = [
        "Runtime",
        "Handler",
        "MemorySize",
        "Timeout",
        "ReservedConcurrencyLimit",
        "DeadLetterConfig",
    ]

    differences = {}
    for field in important_fields:
        old_val = old_config.get(field)
        new_val = new_config.get(field)
        if old_val != new_val:
            differences[field] = {"old": old_val, "new": new_val}

    return differences


def extract_account_ids(data):
    """Extract old and new account IDs from the comparison data."""
    if not data["comparisons"]:
        return "Unknown", "Unknown"

    # Get account IDs from the first comparison's environment variables
    first_comparison = data["comparisons"][0]
    env_diffs = first_comparison["env_var_differences"]["different_values"]

    old_account = "Unknown"
    new_account = "Unknown"

    for diff in env_diffs:
        if "sqs.eu-west-2.amazonaws.com/" in diff["old_value"]:
            old_account = diff["old_value"].split("/")[3]
            new_account = diff["new_value"].split("/")[3]
            break

    return old_account, new_account


def generate_html_report(data, output_file, prefix=None):
    """Generate HTML report from results data."""

    old_account, new_account = extract_account_ids(data)

    title_suffix = f" - {prefix.upper()}" if prefix else ""

    html_template = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Lambda Migration Comparison Report{title_suffix}</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background: #f5f7fa;
            color: #333;
        }}
        .header {{
            text-align: center;
            margin-bottom: 30px;
            padding: 20px;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .header h1 {{
            color: #232f3e;
            margin: 0 0 10px 0;
        }}
        .summary {{
            display: flex;
            justify-content: center;
            gap: 40px;
            margin: 20px 0;
        }}
        .summary-item {{
            text-align: center;
        }}
        .summary-number {{
            font-size: 32px;
            font-weight: bold;
            color: #ff9900;
        }}
        .summary-label {{
            font-size: 14px;
            color: #666;
        }}
        .function-card {{
            background: white;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            overflow: hidden;
        }}
        .function-header {{
            background: #232f3e;
            color: white;
            padding: 15px 20px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .function-header:hover {{
            background: #37475a;
        }}
        .function-name {{
            font-weight: 600;
            font-size: 16px;
        }}
        .status-badge {{
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 600;
            background: #feebea;
            color: #d13212;
        }}
        .function-content {{
            display: none;
            padding: 20px;
        }}
        .function-content.show {{
            display: block;
        }}
        .section {{
            margin-bottom: 25px;
        }}
        .section-title {{
            font-weight: 600;
            color: #232f3e;
            margin-bottom: 10px;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }}
        .env-diff {{
            background: #f8f9fa;
            border-radius: 6px;
            padding: 15px;
            margin-bottom: 15px;
        }}
        .diff-item {{
            margin-bottom: 10px;
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 13px;
        }}
        .diff-removed {{
            color: #d73a49;
            background: #ffeef0;
            padding: 2px 4px;
            border-radius: 3px;
        }}
        .diff-added {{
            color: #28a745;
            background: #f0fff4;
            padding: 2px 4px;
            border-radius: 3px;
        }}
        .diff-key {{
            font-weight: 600;
            color: #6f42c1;
        }}
        .toggle-icon {{
            transition: transform 0.3s ease;
        }}
        .toggle-icon.rotated {{
            transform: rotate(90deg);
        }}
        .accounts-info {{
            display: flex;
            justify-content: space-between;
            margin-bottom: 20px;
            gap: 20px;
        }}
        .account-box {{
            flex: 1;
            background: white;
            padding: 15px;
            border-radius: 6px;
            text-align: center;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }}
        .account-title {{
            font-weight: 600;
            color: #232f3e;
            margin-bottom: 5px;
        }}
        .account-id {{
            font-family: 'Monaco', 'Menlo', monospace;
            color: #666;
            font-size: 14px;
        }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🔄 Lambda Migration Comparison Report{title_suffix}</h1>
        <div class="accounts-info">
            <div class="account-box">
                <div class="account-title">Old Account</div>
                <div class="account-id">{old_account}</div>
            </div>
            <div class="account-box">
                <div class="account-title">New Account</div>
                <div class="account-id">{new_account}</div>
            </div>
        </div>
        <div class="summary">
            <div class="summary-item">
                <div class="summary-number">{data['summary']['old_account_functions']}</div>
                <div class="summary-label">Old Account Functions</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">{data['summary']['new_account_functions']}</div>
                <div class="summary-label">New Account Functions</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">{data['summary']['matched_functions']}</div>
                <div class="summary-label">Matched Functions</div>
            </div>
        </div>
    </div>

    <div id="functions-container"></div>

    <script>
        const data = {json.dumps(data, indent=2)};

        function generateFunctionCards() {{
            const container = document.getElementById('functions-container');

            data.comparisons.forEach((comparison, index) => {{
                const card = document.createElement('div');
                card.className = 'function-card';

                const hasEnvDiffs = comparison.env_var_differences.missing_in_new.length > 0 ||
                                  comparison.env_var_differences.missing_in_old.length > 0 ||
                                  comparison.env_var_differences.different_values.length > 0;

                const hasConfigDiffs = Object.keys(comparison.config_differences).length > 0;

                card.innerHTML = `
                    <div class="function-header" onclick="toggleFunction(${{index}})">
                        <div class="function-name">${{comparison.new_function}}</div>
                        <div>
                            <span class="status-badge">${{comparison.status}}</span>
                            <span class="toggle-icon" id="icon-${{index}}">▶</span>
                        </div>
                    </div>
                    <div class="function-content" id="content-${{index}}">
                        ${{hasConfigDiffs ? generateConfigSection(comparison.config_differences) : ''}}
                        ${{hasEnvDiffs ? generateEnvSection(comparison.env_var_differences) : ''}}
                        ${{!hasConfigDiffs && !hasEnvDiffs ? '<p>No differences found.</p>' : ''}}
                    </div>
                `;

                container.appendChild(card);
            }});
        }}

        function generateConfigSection(configDiffs) {{
            if (Object.keys(configDiffs).length === 0) return '';

            let html = '<div class="section"><div class="section-title">Configuration Differences</div>';

            Object.entries(configDiffs).forEach(([field, values]) => {{
                html += `
                    <div class="env-diff">
                        <div class="diff-item">
                            <span class="diff-key">${{field}}:</span><br>
                            <span class="diff-removed">- ${{values.old}}</span><br>
                            <span class="diff-added">+ ${{values.new}}</span>
                        </div>
                    </div>
                `;
            }});

            html += '</div>';
            return html;
        }}

        function generateEnvSection(envDiffs) {{
            let html = '<div class="section"><div class="section-title">Environment Variable Differences</div>';

            if (envDiffs.missing_in_new.length > 0) {{
                html += '<div class="env-diff">';
                html += '<div class="diff-item"><strong>Missing in New Account:</strong></div>';
                envDiffs.missing_in_new.forEach(key => {{
                    html += `<div class="diff-item"><span class="diff-removed">- ${{key}}</span></div>`;
                }});
                html += '</div>';
            }}

            if (envDiffs.missing_in_old.length > 0) {{
                html += '<div class="env-diff">';
                html += '<div class="diff-item"><strong>New in New Account:</strong></div>';
                envDiffs.missing_in_old.forEach(key => {{
                    html += `<div class="diff-item"><span class="diff-added">+ ${{key}}</span></div>`;
                }});
                html += '</div>';
            }}

            if (envDiffs.different_values.length > 0) {{
                html += '<div class="env-diff">';
                html += '<div class="diff-item"><strong>Changed Values:</strong></div>';
                envDiffs.different_values.forEach(diff => {{
                    html += `
                        <div class="diff-item">
                            <span class="diff-key">${{diff.key}}:</span><br>
                            <span class="diff-removed">- ${{diff.old_value}}</span><br>
                            <span class="diff-added">+ ${{diff.new_value}}</span>
                        </div>
                    `;
                }});
                html += '</div>';
            }}

            html += '</div>';
            return html;
        }}

        function toggleFunction(index) {{
            const content = document.getElementById(`content-${{index}}`);
            const icon = document.getElementById(`icon-${{index}}`);

            if (content.classList.contains('show')) {{
                content.classList.remove('show');
                icon.classList.remove('rotated');
                icon.textContent = '▶';
            }} else {{
                content.classList.add('show');
                icon.classList.add('rotated');
                icon.textContent = '▼';
            }}
        }}

        // Initialize the page
        generateFunctionCards();
    </script>
</body>
</html>"""

    with open(output_file, 'w') as f:
        f.write(html_template)

    return output_file


def main():
    parser = argparse.ArgumentParser(
        description="Compare specific Lambda functions between AWS accounts"
    )
    parser.add_argument("--old-account", required=True, help="Old AWS account ID")
    parser.add_argument("--new-account", required=True, help="New AWS account ID")
    parser.add_argument("--old-profile", required=True, help="AWS profile for old account")
    parser.add_argument("--new-profile", required=True, help="AWS profile for new account")
    parser.add_argument(
        "--old-region", default="eu-west-2", help="Region for old account"
    )
    parser.add_argument(
        "--new-region", default="eu-west-2", help="Region for new account"
    )
    parser.add_argument(
        "--prefix",
        help='Prefix for functions in both accounts (e.g., "dev", "authdev1")',
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Compare all Lambda functions instead of just the target list"
    )
    parser.add_argument("--output", help="Output file for results (JSON)")

    args = parser.parse_args()

    # Initialize sessions first (this is where SSO login happens)
    print(f"Authenticating with old account ({args.old_account})...")
    old_session = get_session(args.old_profile)

    print(f"Authenticating with new account ({args.new_account})...")
    new_session = get_session(args.new_profile)

    # Create clients from sessions (no additional auth needed)
    old_lambda = get_lambda_client(old_session, args.old_region)
    new_lambda = get_lambda_client(new_session, args.new_region)

    print(f"Fetching Lambda functions from old account ({args.old_account})...")

    # Fetch from both accounts in parallel
    with ThreadPoolExecutor(max_workers=2) as executor:
        old_future = executor.submit(list_lambdas, old_lambda)
        new_future = executor.submit(list_lambdas, new_lambda)

        old_functions = old_future.result()
        new_functions = new_future.result()

    print(f"Found {len(old_functions)} functions in old account")
    print(f"Found {len(new_functions)} functions in new account")

    # Find matching functions
    if args.all:
        print(f"\nComparing ALL Lambda functions")
        if args.prefix:
            print(f"  With prefix filter: {args.prefix}")
    else:
        print(f"\nComparing specific Lambda functions")
        if args.prefix:
            print(f"  With prefix: {args.prefix}")

    matches = find_matching_functions(
        old_functions,
        new_functions,
        args.prefix,
        args.all,
    )

    results = {
        "summary": {
            "old_account_functions": len(old_functions),
            "new_account_functions": len(new_functions),
            "matched_functions": len(matches),
        },
        "comparisons": [],
    }

    # Compare matched functions
    for new_name, old_name in matches.items():
        new_func = new_functions[new_name]
        old_func = old_functions[old_name]

        print(f"\nComparing {old_name} -> {new_name}")

        # Compare configurations
        config_diff = compare_function_config(
            old_func["config"], new_func["config"]
        )

        # Compare environment variables
        env_diff = compare_env_vars(old_func["env_vars"], new_func["env_vars"])

        comparison = {
            "old_function": old_name,
            "new_function": new_name,
            "config_differences": config_diff,
            "env_var_differences": env_diff,
            "status": "PASS"
            if not config_diff and not any(env_diff.values())
            else "REVIEW",
        }

        results["comparisons"].append(comparison)

        # Print summary
        if comparison["status"] == "PASS":
            print("  ✅ PASS - No significant differences")
        else:
            print("  ⚠️  REVIEW - Differences found:")

            # Show config differences
            if config_diff:
                print("    📋 Config differences:")
                for field, values in config_diff.items():
                    print(f"      {field}: {values['old']} -> {values['new']}")

            # Show env var differences
            if env_diff["missing_in_new"]:
                print(
                    f"    🔴 Missing env vars in new: {env_diff['missing_in_new']}"
                )
            if env_diff["missing_in_old"]:
                print(f"    🟡 New env vars: {env_diff['missing_in_old']}")
            if env_diff["different_values"]:
                print("    🔄 Changed env vars:")
                for diff in env_diff["different_values"]:
                    print(
                        f"      {diff['key']}: '{diff['old_value']}' -> '{diff['new_value']}'"
                    )

    # Output results
    if args.output:
        with open(args.output, "w") as f:
            json.dump(results, f, indent=2, default=str)
        print(f"\nResults saved to {args.output}")

        # Generate HTML report
        html_filename = f"lambda-comparison-report-{args.prefix}.html" if args.prefix else "lambda-comparison-report.html"
        html_path = generate_html_report(results, html_filename, args.prefix)
        print(f"HTML report generated: {html_path}")

    # Summary
    total_comparisons = len(results["comparisons"])
    passed = sum(1 for c in results["comparisons"] if c["status"] == "PASS")

    print("\n📊 Summary:")
    print(f"  Total comparisons: {total_comparisons}")
    print(f"  Passed: {passed}")
    print(f"  Need review: {total_comparisons - passed}")


if __name__ == "__main__":
    main()
