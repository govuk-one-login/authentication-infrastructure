import logging
import os

import urllib3


def test_egress(domain, domain_type, timeout):
    try:
        if domain_type == "blocked":
            logging.captureWarnings(True)
        http = urllib3.PoolManager(retries=False, timeout=timeout)
        print("Testing connection to " + domain)
        response = http.request("GET", domain)
        print("Received a response: " + str(response.status))
        return True
    except urllib3.exceptions.HTTPError as error:
        if domain_type != "blocked":
            print("Test failed for: " + domain)
            print(error)
        else:
            print("Test passed for " + domain)
        return False


def print_summary(type, errors, domains):
    print("Summary for " + type + " domains:")
    error_prefix = "Failed to reach: "
    fail_summary_prefix = "Couldn't reach the following "
    pass_summary_prefix = "All "
    if type == "blocked":
        error_prefix = "Successfully reached: "
        fail_summary_prefix = "We were able to reach the following "
        pass_summary_prefix = "No "
    if len(errors) > 0:
        print(
            error_prefix + str(len(errors)) + " of " + str(len(domains)) + " domains."
        )
        print(fail_summary_prefix + type + " domains: ")
        for domain in errors:
            print("FAIL: " + domain)
    else:
        print(pass_summary_prefix + type + " domains are reachable:")
        for domain in domains:
            print("PASS: " + domain)


def parse_errors(
    default_errors,
    default_domains,
    custom_errors,
    custom_domains,
    blocked_errors,
    blocked_domains,
):
    print_summary("default", default_errors, default_domains)
    print_summary("custom", custom_errors, custom_domains)
    print_summary("blocked", blocked_errors, blocked_domains)
    if len(custom_errors) > 0 and len(default_errors) == 0:
        print(
            "Only custom domains unreachable. Check the Network Firewall rules and AllowedDomains for this VPC stack."
        )
    if len(blocked_errors) > 0:
        print(
            "Domains that should be blocked are reachable. Check that the Network Firewall is enabled for this environment's TGW."
        )


def lambda_handler(event, context):
    default_domains = str.split(os.environ.get("DEFAULT_URLS"), ",")
    custom_domains = (
        []
        if os.environ.get("CUSTOM_URLS") == ""
        else str.split(os.environ.get("CUSTOM_URLS"), ",")
    )
    blocked_domains = str.split(os.environ.get("BLOCKED_URLS"), ",")
    timeout = int(os.environ.get("TIMEOUT", 5))
    default_errors = []
    custom_errors = []
    blocked_errors = []
    for domain in default_domains:
        connected = test_egress(domain, "default", timeout)
        if not connected:
            default_errors.append(domain)
    for domain in custom_domains:
        connected = test_egress(domain, "custom", timeout)
        if not connected:
            custom_errors.append(domain)
    for domain in blocked_domains:
        connected = test_egress(domain, "blocked", timeout)
        if connected:  # we shouldn't be able to hit these
            blocked_errors.append(domain)
    parse_errors(
        default_errors,
        default_domains,
        custom_errors,
        custom_domains,
        blocked_errors,
        blocked_domains,
    )
