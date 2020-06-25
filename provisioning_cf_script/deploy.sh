#!/bin/bash

# ##################################################
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.

# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so.
# ##################################################

# define environment label [test/dev/prod...]
if [[ -z "$ENVIRONMENT" ]]; then
	ENVIRONMENT=test
	echo "Environment variable not specified. Using default: test"
fi
echo "Using Environment $ENVIRONMENT"


# define aws profile used as --profle YOUR_ACCOUNT
if [ -z "$AWS_PROFILE" ]; then
	echo "Environment variable not specified. Using aws configure without a profile."
fi
echo "Using Region $AWS_PROFILE"
AWS_ARGS="--profile $AWS_PROFILE"

# get the region account is using
AWS_REGION=$(aws configure get region ${AWS_ARGS})
echo "Using Region $AWS_REGION"

# get the account ID to name the S3 asset bucket we are about to create
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account' $AWS_ARGS)
echo account id: $AWS_ACCOUNT_ID

#create S3 bucket
S3_BUCKET="greengrass-deepstream-$AWS_ACCOUNT_ID-${ENVIRONMENT}-assets"
echo "Bucket name : $S3_BUCKET";
#check if bucket exists
bucketstatus=$(aws s3api head-bucket --bucket "${S3_BUCKET}" $AWS_ARGS 2>&1)
if [ -z "$bucketstatus" ]
then
	echo "Bucket exists: $S3_BUCKET, using existing bucket."
else
	echo "Bucket does not exist, creating new bucket."
	if [ $AWS_REGION == "us-east-1" ];
	then
		echo "using us-east-1"
		aws s3api create-bucket --bucket "$S3_BUCKET" $AWS_ARGS;
	else
	   aws s3api create-bucket --bucket "$S3_BUCKET" --create-bucket-configuration LocationConstraint="$AWS_REGION" $AWS_ARGS;  
        fi
fi

# Decide whether to create new thing for this deployment
GG_THING_EXISTS=$(aws iot describe-thing --thing-name $GG_THING_GROUP_NAME $AWS_ARGS --query 'thingArn')
DS_THING_EXISTS=$(aws iot describe-thing --thing-name $DS_THING_GROUP_NAME $AWS_ARGS --query 'thingArn')

#check if thing exists, and create if they do not currently exist
if [ -z "$GG_THING_EXISTS" ] || [ -z "$DS_THING_EXISTS" ]
then
	echo "Thing does not exist, creating GG and GGDS things"
	GGDP_PROV_STACK_NAME="greengrass-deepstream-provisioning-$AWS_ACCOUNT_ID-$AWS_REGION-$ENVIRONMENT-stack"
	echo "Deploying Greengrass-Deepstream Provisioning Stack environment: $ENVIRONMENT, S3 bucket: $S3_BUCKET, Cloudformation Stack: $GGDP_PROV_STACK_NAME"
	sam package \
		--template-file ./provision-greengrass.yml \
		--s3-bucket $S3_BUCKET \
		--output-template-file ./provision-packaged.yaml $AWS_ARGS
	sam deploy \
		--template-file ./provision-packaged.yaml \
		--stack-name $GGDP_PROV_STACK_NAME \
		--parameter-overrides \
			ParameterKey=CoreName,ParameterValue=$GG_THING_GROUP_NAME \
			ParameterKey=DeepstreamAppThingName,ParameterValue=$DS_THING_GROUP_NAME \
			S3BucketName=$S3_BUCKET \
		--capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND $AWS_ARGS
else
	echo "The thing name already exist, please modify deploy.env, source it, and try this script again."
fi

# generate pre-signed S3 links to download certificates for Greengrass
echo sudo wget -O /greengrass/certs/certificatePem.cert.pem \"$(aws s3 presign s3://$S3_BUCKET/$GG_THING_GROUP_NAME/certs/certificatePem.cert.pem --expires-in 604800 $AWS_ARGS)\" >> ../formation_cf_script/install_greengrass.sh
echo sudo wget -O /greengrass/certs/privateKey.private.key \"$(aws s3 presign s3://$S3_BUCKET/$GG_THING_GROUP_NAME/certs/privateKey.private.key --expires-in 604800 $AWS_ARGS)\" >> ../formation_cf_script/install_greengrass.sh
echo sudo wget -O /greengrass/config/config.json \"$(aws s3 presign s3://$S3_BUCKET/$GG_THING_GROUP_NAME/config/config.json --expires-in 604800 $AWS_ARGS)\" >> ../formation_cf_script/install_greengrass.sh

# Certs generated for DeepStream app to connect to IoT or Greengrass
echo sudo wget -O /opt/nvidia/deepstream/deepstream-5.0/sources/libs/aws_protocol_adaptor/device_client/certs/certificatePem.cert.pem \"$(aws s3 presign s3://$S3_BUCKET/$DS_THING_GROUP_NAME/certs/certificatePem.cert.pem --expires-in 604800 $AWS_ARGS)\" > ../output.txt
echo sudo wget -O /opt/nvidia/deepstream/deepstream-5.0/sources/libs/aws_protocol_adaptor/device_client/certs/privateKey.private.key \"$(aws s3 presign s3://$S3_BUCKET/$DS_THING_GROUP_NAME/certs/privateKey.private.key --expires-in 604800 $AWS_ARGS)\" >> ../output.txt
echo sudo wget -O /opt/nvidia/deepstream/deepstream-5.0/sources/libs/aws_protocol_adaptor/device_client/certs/root.ca.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem >> ../output.txt

# Environmental variable
echo S3_BUCKET=\"$S3_BUCKET\" >> ../deploy.env
