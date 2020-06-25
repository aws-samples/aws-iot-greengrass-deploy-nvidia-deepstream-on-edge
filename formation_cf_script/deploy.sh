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
	echo "Bucket does not exist, creating new bucket.";
	aws s3api create-bucket --bucket "$S3_BUCKET" --create-bucket-configuration LocationConstraint="$AWS_REGION" $AWS_ARGS;  
fi

# Decide whether to create new thing for this deployment
GG_THING_EXISTS=$(aws iot describe-thing --thing-name $GG_THING_GROUP_NAME $AWS_ARGS --query 'thingArn')
DS_THING_EXISTS=$(aws iot describe-thing --thing-name $DS_THING_GROUP_NAME $AWS_ARGS --query 'thingArn')

#check if thing exists, and create if they do not currently exist
if [ -z "$GG_THING_EXISTS" ] || [ -z "$DS_THING_EXISTS" ]
then
	echo "ERROR: The thing name to associate this Greengrass Core we are about to create does not exist."
	echo "Please run provision script first."
else
	# Deploy or update
	GGDP_STACK_NAME="greengrass-deepstream-$AWS_ACCOUNT_ID-$AWS_REGION-${ENVIRONMENT}-stack"
	echo "Deploying Greengrass Stack env: $ENVIRONMENT, s3: $S3_BUCKET, greengrass-deepstream-stack: $GGDP_STACK_NAME with $AWS_ARGS"

	sam package \
		--template-file ./form-greengrass_modules.yml \
		--s3-bucket $S3_BUCKET \
		--output-template-file ./form-greengrass_modules-packaged.yaml $AWS_ARGS
	sam deploy \
		--template-file ./form-greengrass_modules-packaged.yaml \
		--stack-name $GGDP_STACK_NAME \
		--parameter-overrides \
			CoreName=$GG_THING_GROUP_NAME \
			S3BucketName=$S3_BUCKET \
			MLResourceName=$ML_RESOURCE_NAME \
		--capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND $AWS_ARGS
fi
