import os

import boto3
import cfnresponse
from boto3.session import Session
from botocore.exceptions import ClientError

ec2_client = boto3.client("ec2")
region = os.environ["AWS_REGION"]
ipampool = os.environ["IPAMPOOL"]
session = Session(region_name=region)


def describe_ipam_pool(session: Session):
    paginator = ec2_client.get_paginator("describe_ipam_pools").paginate(
        DryRun=False, Filters=[{"Name": "locale", "Values": [region]}]
    )

    for page in paginator:
        for ip_pool in page["IpamPools"]:
            yield ip_pool


def find_ipam_pool_id(ipam_pools):
    for ip_pool in ipam_pools:
        for tag in ip_pool["AllocationResourceTags"]:
            if tag["Key"] == "IpamPool" and tag["Value"] == ipampool:
                ip_pool_id = ip_pool["IpamPoolId"]
                return ip_pool_id


def lambda_handler(event, context):
    responseData = {}
    if event["RequestType"] == "Create":
        try:
            ipam_pools = describe_ipam_pool(session)

            ipam_pool_id = find_ipam_pool_id(ipam_pools)

            responseData["Data"] = ipam_pool_id

            if ipam_pool_id is None:
                cfnresponse.send(
                    event,
                    context,
                    cfnresponse.FAILED,
                    "No IPAM Pools with Allocation Resource Tags that match the Environment",
                )
            else:
                cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)

        except ClientError as e:
            print(e.response["Error"]["Message"])
            cfnresponse.send(event, context, cfnresponse.FAILED, e.response)

    if event["RequestType"] == "Update":
        cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)

    if event["RequestType"] == "Delete":
        # We expect IPAM to release the allocation per: https://docs.aws.amazon.com/vpc/latest/ipam/release-alloc-ipam.html
        cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)
