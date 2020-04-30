# ##################################################
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.

# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so.
# ##################################################

import sys
import cfnresponse
import boto3
from botocore.exceptions import ClientError
import json
import logging
import os
logger = logging.getLogger()
logger.setLevel(logging.INFO)
S3BUCKETNAME = os.environ['S3BUCKETNAME']
policyDocument = {
    'Version': '2012-10-17',
    'Statement': [
        {
            'Effect': 'Allow',
            'Action': 'iot:*',
            'Resource': '*'
        },
        {
            'Effect': 'Allow',
            'Action': 'greengrass:*',
            'Resource': '*'
        }
    ]
}


def handler(event, context):
    responseData = {}
    try:
        logger.info('Received event: {}'.format(json.dumps(event)))
        result = cfnresponse.FAILED
        client = boto3.client('iot')
        thingName = event['ResourceProperties']['ThingName']
        if event['RequestType'] == 'Create':
            thing = client.create_thing(
                thingName=thingName
            )
            response = client.create_keys_and_certificate(
                setAsActive=True
            )
            certId = response['certificateId']
            certArn = response['certificateArn']
            certPem = response['certificatePem']
            privateKey = response['keyPair']['PrivateKey']
            publicKey = response['keyPair']['PublicKey']
            client.create_policy(
                policyName='{}-full-access'.format(thingName),
                policyDocument=json.dumps(policyDocument)
            )
            response = client.attach_policy(
                policyName='{}-full-access'.format(thingName),
                target=certArn
            )
            response = client.attach_thing_principal(
                thingName=thingName,
                principal=certArn,
            )

            logger.info('Created thing: %s, cert: %s and policy: %s' %
                        (thingName, certId, '{}-full-access'.format(thingName)))
            result = cfnresponse.SUCCESS
            s3 = boto3.resource('s3')
            responseData['certificateArn'] = certArn
            responseData['certificateId'] = certId
            responseData['certificatePem'] = certPem
            s3_obj = s3.Object(S3BUCKETNAME, thingName +
                               '/certs/certificatePem.cert.pem')
            s3_obj.put(Body=certPem)
            responseData['privateKey'] = privateKey
            s3_obj = s3.Object(S3BUCKETNAME, thingName +
                               '/certs/privateKey.private.key')
            s3_obj.put(Body=privateKey)
            s3_obj = s3.Object(S3BUCKETNAME, thingName +
                               '/certs/publicKey.public.key')
            s3_obj.put(Body=publicKey)
            responseData['iotEndpoint'] = client.describe_endpoint(
                endpointType='iot:Data-ATS')['endpointAddress']
            responseData['thingArn'] = thing["thingArn"]
            if "Region" in event['ResourceProperties']:
                config_string = """{{
    "coreThing" : {{
    "caPath" : "root.ca.pem",
    "certPath" : "certificatePem.cert.pem",
    "keyPath" : "privateKey.private.key",
    "thingArn" : "{}",
    "iotHost" : "{}",
    "ggHost" : "greengrass-ats.iot.{}.amazonaws.com",
    "keepAlive" : 600
    }},
    "runtime" : {{
    "cgroup" : {{
        "useSystemd" : "yes"
    }},
    "allowFunctionsToRunAsRoot" : "yes"
    }},
    "managedRespawn" : false,
    "crypto" : {{
    "principals" : {{
        "SecretsManager" : {{
        "privateKeyPath" : "file:///greengrass/certs/privateKey.private.key"
        }},
        "IoTCertificate" : {{
        "privateKeyPath" : "file:///greengrass/certs/privateKey.private.key",
        "certificatePath" : "file:///greengrass/certs/certificatePem.cert.pem"
        }}
    }},
    "caPath" : "file:///greengrass/certs/root.ca.pem"
    }}
}}
""".format(responseData["thingArn"], responseData['iotEndpoint'], event['ResourceProperties']['Region'])
                s3_obj = s3.Object(S3BUCKETNAME, thingName +
                                   '/config/config.json')
                s3_obj.put(Body=config_string)
        elif event['RequestType'] == 'Update':
            logger.info('Updating thing: %s' % thingName)
            result = cfnresponse.SUCCESS
        elif event['RequestType'] == 'Delete':
            logger.info('Deleting thing: %s and cert/policy' % thingName)
            response = client.list_thing_principals(
                thingName=thingName
            )
            for i in response['principals']:
                response = client.detach_thing_principal(
                    thingName=thingName,
                    principal=i
                )
                response = client.detach_policy(
                    policyName='{}-full-access'.format(thingName),
                    target=i
                )
                response = client.update_certificate(
                    certificateId=i.split('/')[-1],
                    newStatus='INACTIVE'
                )
                response = client.delete_certificate(
                    certificateId=i.split('/')[-1],
                    forceDelete=True
                )
                response = client.delete_policy(
                    policyName='{}-full-access'.format(thingName),
                )
                response = client.delete_thing(
                    thingName=thingName
                )
            result = cfnresponse.SUCCESS
    except ClientError as e:
        logger.error('Error: {}'.format(e))
        result = cfnresponse.FAILED
    logger.info('Returning response of: {}, with result of: {}'.format(
        result, responseData))
    sys.stdout.flush()
    cfnresponse.send(event, context, result, responseData)
