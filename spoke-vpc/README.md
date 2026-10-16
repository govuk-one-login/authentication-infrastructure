# VPC

CloudFormation template for deploying a virtual private cloud (VPC).

## Deployment Modes

You can use this template to deploy either:

* a "Legacy" VPC, which contains its own networking resources for making egress requests
* a "Spoke" VPC, which uses the Transit Gateway Hub for making egress requests

This README explains how to configure the template to deploy either type of VPC, including both mandatory and optional configuration parameters.

Configure the template to deploy a Spoke VPC if you're migrating your service to the Transit Gateway Hub, or building a new service.

Use the Legacy VPC configuration if you are updating your VPC template but aren't currently migrating to the Transit Gateway Hub.

> **⚠️ Important:** Any configurable parameters omitted from the sections below are type-agnostic and applicable to both VPC modes. For details regarding these shared parameters, please review their descriptions or visit the comprehensive VPC template [documentation page][1].

# Legacy Mode Deployments

## Description

The original deployment mode for the VPC template, known as the Legacy VPC architecture, establishes an autonomous Virtual Private Cloud complete with its own Network Firewall, NAT Gateways, and egress infrastructure. It handles outbound connectivity independently by utilising Suricata-based Network Firewall rules and NAT Gateway Elastic IP addresses to govern internet-bound traffic.

This mode is appropriate for workloads that have not initiated the migration process to the Transit Gateway. Currently, the Dev-Platform team is in the process of transitioning all Legacy VPCs over to the Spoke VPC architecture. For any questions regarding this migration or for advice on selecting the correct VPC deployment mode, please contact the team via the support workflow located in the [#di-dev-platform][3] Slack channel.

To find out more, review the main [documentation page][1]. If you need to set up the Dynatrace VPC endpoint, refer to its dedicated [documentation page][2].

> **⚠️ Important:** The template defaults to Legacy mode if the `VpcType` parameter remains unmodified.

## Required parameters for Legacy VPC deployments

### `VpcType`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[TYPE-AGNOSTIC]` | `Legacy` (default) <br> `Spoke` | Yes |

Determines whether the template provisions the original Legacy Virtual Private Cloud (VPC)
architecture or the recently released Transit Gateway-attached architecture referred to as Spoke VPC.

> **⚠️ Important:** To deploy in Legacy VPC mode, leave this parameter at its default value of `Legacy`. If this parameter is set to `Spoke`, any Legacy-specific parameters will be rejected and the deployment will fail.

---

### `CidrBlock`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `10.0.0.0/16` (default) <br> A valid IPv4 CIDR block | Yes |

The CIDR block that defines the IP range the VPC will use. This defaults to `10.0.0.0/16` and there is no specific reason to change this unless you have multiple VPCs that are going to be peered.

> **Note:** This parameter is not used in Spoke VPC mode where IPAM handles IP allocation automatically.

---

### `AvailabilityZoneCount`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `3` (default) <br> `2` | No |

The number of availability zones to configure. It is expected that AWS will be more reliable than our application and as such two availability zones should be sufficient for the vast majority of use cases.

> **Note:** For Spoke VPC deployments, the availability zone count is not configurable and therefore will always be 3.

  ---

## Optional parameters for Legacy VPC deployments

Along with the required parameters there are some optional ones that can be configured for Legacy VPC deployments.

### NAT Gateway EIP Configuration: `ZoneAEIPAllocationId`/`ZoneBEIPAllocationId`/`ZoneCEIPAllocationId`

Allows teams to specify pre-allocated Elastic IP (EIP) addresses for the NAT Gateways in each availability zone. If not specified, EIPs will be automatically provisioned.

#### `ZoneAEIPAllocationId`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `"none"` (default) <br> Elastic IP Allocation ID (string) | No |

The Elastic IP allocation ID to use for the NAT Gateway in Availability Zone A. If not specified, an Elastic IP will be automatically provisioned.

#### `ZoneBEIPAllocationId`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `"none"` (default) <br> Elastic IP Allocation ID (string) | No |

The Elastic IP allocation ID to use for the NAT Gateway in Availability Zone B. If not specified, an Elastic IP will be automatically provisioned.

#### `ZoneCEIPAllocationId`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `"none"` (default) <br> Elastic IP Allocation ID (string) | No |

The Elastic IP allocation ID to use for the NAT Gateway in Availability Zone C. If not specified, an Elastic IP will be automatically provisioned. This will only be used if `AvailabilityZoneCount` is set to `3`.

---

### Egress Firewall Rules: `AllowRules`/`AdditionalAllowRules`

Controls outbound traffic from the VPC using Suricata-based Network Firewall rules. These rules determine which external destinations are permitted for egress traffic.

#### `AllowRules`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `""` (default) <br> A valid Suricata rule (string) | No |

> **Note:** Custom Suricata rules should only be used when these are required to pass traffic which cannot be provisioned using `AllowedDomains`. Consecutive Signature ID (SIDs) are used. To enable egress, you must fill the `AllowedDomains` or `AllowRules`(/ `AdditionalAllowRules`) parameters.

> **Example rule** to allow traffic for all domains under `account.gov.uk`: pass tls $HOME_NET any -> $EXTERNAL_NET 443 (tls.sni; content:".account.gov.uk"; endswith; msg:"Pass TLS to *.account.gov.uk"; flow:established; sid:2001; rev:1;). For further information on using Suricata Rules see [How to write Suricata Policies for Egress access][4].

#### `AdditionalAllowRules`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `""` (default) <br> A valid Suricata rule (string) | No |

Additional Suricata rules needed to pass traffic. This parameter is for when the maximum character length of the `AllowRules` parameter has been reached but more rules are required.

---

### Logging Configuration: `FirewallS3Bucket`/`NLBAccessLogsBucketName`

#### `FirewallS3Bucket`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `"log-archive-nwf-alerts-logs-523017967436-eu-west-2"` (default) <br> S3 bucket name (string) | No |

The S3 bucket destination for Network Firewall logs. Defaults to the central log archive account bucket.

#### `NLBAccessLogsBucketName`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| [`LEGACY VPC ONLY]` | `"log-archive-nlb-access-logs-523017967436-eu-west-2"` (default) <br> S3 bucket name string | No |

The bucket name for Network Load Balancer access logs destination. Defaults to a bucket in the central log archive account.

---

### VPC Peering Configuration: `VpcPeeringConnectionId`/`VpcPeeringRequesterCidr`

> **Note**: Please DO NOT USE unless in the Orchestration or Authentication team.

Created for the Orchestration/Authentication Secure Pipelines migration to allow for cross-account DynamoDB access. These parameters configure route table entries for an existing VPC peering connection.

#### `VpcPeeringConnectionId`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `"none"` (default) <br> pre-existing VPC Peering Connection ID (string) | No |

> **⚠️ Important:** The peering connection must exist beforehand. This is not a bootstrap parameter.

#### `VpcPeeringRequesterCidr`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `"none"` (default) <br> A valid IPv4 CIDR block (string) | No |

The IPv4 CIDR address block of the other VPC of an existing VPC peering connection.

> **⚠️ Important:** The peering connection must exist beforehand. This is not a bootstrap parameter.

---

### `LogsApiEnabled`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[LEGACY VPC ONLY]` | `No` (default) <br> `Yes` | No |

The CloudWatch Logs API is enabled. This is not required for a Lambda to emit logging events by writing to standard output. This is required if the Lambda explicitly writes logs to a log group or for container logging.

> **Note:** this API endpoint is only available to Legacy VPCs. For Spoke VPCs only `CloudWatchLogsApiEnabled` is available. `LogsApiEnabled` is a duplicate of `CloudWatchLogsApiEnabled` and will be removed once migration to use Transit Gateway is completed on the programme.

---

# Spoke Mode Deployments

## Description

By provisioning a Transit Gateway-attached Virtual Private Cloud, the Spoke VPC architecture systematically channels all outbound traffic through a centralised Transit Gateway Hub.

This model delegates egress control to the shared hub infrastructure instead of requiring each VPC to maintain its own independent NAT Gateways and Network Firewalls. Consequently, this lowers per-account management overhead and guarantees uniform security policy enforcement throughout the organisation.

To prevent cross-account IP resource overlapping, Spoke VPCs utilise AWS IPAM (IP Address Manager) for automated CIDR allocation. The integrated Transit Gateway attachment offers a unified, fully managed egress path with centralised firewall inspection, and also allows disaster recovery paths for Production environments to be pre-provisioned and executed on-demand during operational incidents.

This setup is highly recommended for all new VPC stack deployments and represents the strategic direction for VPC provisioning within the programme.

> **⚠️ Important:** Please be aware that Spoke is not the default deployment model. You must explicitly set the `VpcType` parameter to `Spoke` when deploying a Spoke VPC.

## Required parameters for Spoke VPC deployments

### `VpcType`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[TYPE-AGNOSTIC]` | `Legacy` (default) <br> `Spoke` | Yes |

Determines whether the template provisions the original Legacy Virtual Private Cloud (VPC) architecture or the recently released Transit Gateway-attached architecture referred to as Spoke VPC.

To deploy in Spoke VPC mode this parameter must be set to `Spoke`. If this parameter is not switched from the default value (`Legacy`) to `Spoke` the deployment will fail if any other Spoke VPC-specific parameters are selected since `[SPOKE VPC ONLY]` parameters cannot be used when deploying in Legacy mode.

> **⚠️ Important:** Spoke is not the default deployment mode. You must actively select to change this parameter value when deploying a Spoke VPC.

---
### `Environment`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[SPOKE VPC ONLY]` | `Development` (default) <br> `Demo` <br> `Build` <br> `Staging` <br> `Integration` <br> `Production` | Yes |

For selecting the environment that the Spoke VPC will be deployed in. This parameter determines three things automatically via a look-up mapping:

- **IPAM Pool** — which IP address pool the Spoke VPC's CIDR is allocated from (ensures no IP conflicts across the organisation).
- **Transit Gateway ID** — which Transit Gateway handles egress traffic for this environment.
- **Disaster Recovery Transit Gateway ID** — the fallback Transit Gateway for DR scenarios (only configured and available for Production).

> **Note:** You must set this to match the environment of the AWS account the Spoke VPC will be deployed in so that the corresponding Transit Gateway Hub environment configuration is applied.

---

## Optional parameters for Spoke VPC deployments

Along with the required parameters there are some optional ones that can be selected to enable Spoke VPC additional features.

### Egress Testing Configuration: `DeployEgressTestLambda`/`EgressTestLambdaCustomURLs`

Allows teams to deploy an EgressTestLambda function directly into a Spoke VPC to ensure outbound network paths are operating as expected. By validating created routes via the Transit Gateway, this utility confirms the correct connectivity settings and removes uncertainty during initial deployments or subsequent architecture and configuration.

#### `DeployEgressTestLambda`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[SPOKE VPC ONLY]` | `No` (default) <br> `Yes` | No |

Enabling this option provisions the test lambda within your VPC network layout. When triggered, the function validates communication against three target destinations:

1. A default system baseline URL — `https://signin.account.gov.uk/`
2. Any team-specific custom URLs defined via the `EgressTestLambdaCustomURLs` parameter
3. A known blocked URL — `https://gds-way.digital.cabinet-office.gov.uk/` — to confirm firewall rules are successfully denying non-permitted traffic

Use this Lambda function during initial setup or after configuration changes to validate that egress routing is working as expected.

#### `EgressTestLambdaCustomURLs`

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[SPOKE VPC ONLY]` | `"none"` (default) <br> `"String"` | No |

Allows development teams to verify destination requirements unique to their application. Input endpoints must be provided as a comma-separated list of strings that explicitly include the networking protocol (such as `https://api.example.com`). These settings are directly injected as the `CUSTOM_URLS` environment variable on the EgressTestLambda.

> **Note:** `EgressTestLambdaCustomURLs` requires `DeployEgressTestLambda` to be configured as `Yes` to take effect since `EgressTestLambdaCustomURLs` cannot be applied as a variable value to a Lambda function that has not been provisioned.

See [Egress Test Lambda documentation][5] to review the technical details regarding the execution of the EgressTestLambda and guidance on the analysis of diagnostic logs for this utility.

### UseDisasterRecovery

| VPC Type | Allowed Values | Required |
|----------|----------------|----------|
| `[SPOKE VPC ONLY]` | `No` (default) <br> `Yes` | No |

> **⚠️ Important:** PLEASE DO NOT CHANGE FROM DEFAULT VALUE `NO` UNLESS YOU ARE IN A CO-ORDINATED DISASTER RECOVERY SCENARIO AND HAVE BEEN INSTRUCTED TO DO SO BY THE PLATFORM AND SITE RELIABILITY TEAM.

Enabling this option redirects VPC egress traffic through the Disaster Recovery Transit Gateway by activating the pre-provisioned disaster recovery attachment as the egress path instead of the primary Production egress Transit Gateway route.

This feature is only applicable to environments that have a Disaster Recovery Transit Gateway configured and pre-provisioned, which is currently limited to Production.

> **⚠️ Important:** Under normal operating conditions, this parameter must always be set to `No`. It should only be changed to `Yes` as part of a coordinated disaster recovery. Separating provisioning from activation means the disaster recovery attachment can exist dormant and only be switched on during an incident — without requiring a stack to create infrastructure under pressure and saving time.

[1]: https://govukverify.atlassian.net/wiki/x/AQCC0g
[2]: https://govukverify.atlassian.net/wiki/x/nwER4w
[3]: https://gds.slack.com/archives/C02U78Y5J3H
[4]: https://govukverify.atlassian.net/wiki/x/6wCZzw
[5]: https://govukverify.atlassian.net/wiki/x/y4AgUwE
