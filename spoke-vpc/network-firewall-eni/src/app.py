import json
import time

import boto3
from crhelper import CfnResource

helper = CfnResource()


@helper.create
@helper.update
def get_firewall_subnet_eni(event, _):
    properties = event["ResourceProperties"]
    firewall_arn = properties["FirewallArn"]
    subnet_id = properties["SubnetId"]

    client = boto3.client("network-firewall")
    for i in range(0, 20):
        firewall = client.describe_firewall(FirewallArn=firewall_arn)
        for region_details in firewall["FirewallStatus"]["SyncStates"]:
            attachment_details = firewall["FirewallStatus"]["SyncStates"][
                region_details
            ]["Attachment"]
            print("Go %d: details %s", i, json.dumps(attachment_details))
            if (
                attachment_details["SubnetId"] == subnet_id
                and attachment_details["Status"] == "READY"
            ):
                helper.Data["EndpointId"] = attachment_details["EndpointId"]
                break
        if "EndpointId" in helper.Data:
            break
        else:
            time.sleep(6)


@helper.delete
def no_op(_, __):
    pass


def lambda_handler(event, context):
    helper(event, context)
