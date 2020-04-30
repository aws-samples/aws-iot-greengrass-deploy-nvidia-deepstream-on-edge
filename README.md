## AWS IoT Greengrass Deploying NVIDIA DeepStream on Edge
This is the cloudformation package to demonstrate Machine Learning model deployment at scale with AWS Greengrass on NVIDIA Jetson Devices. This demonstrates consists three parts:
1. Create IoT Things and attach certificates for Greengrass core thing and DeepStream app thing, which will later be attached to this Greengrass group
2. Create a Greengrass core with modules attached
3. Deploy Greengrass on edge device and run DeepStream App
Please follow the steps below to go through the Cloudformation Example:
=============

## Part 1: Create things on AWS IoT
For this part, we are going to use the contents in provisioning_cf_script folder.
```
	cd provisioning_cf_script
```
### Step 1: Configure environment
In order to fully run this example, you will need an aws account with admin access. 
And you will need AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html.
After you get your promatic access credentials from aws account admin user, you can run:
```
	aws configure --profile ANY_NAME_YOU_LIKE
```
After you have your profile ready, please edit deploy.env file to replace my_test_account to ANY_NAME_YOU_LIKE. You can also edit AWS_REGION and ENVIRONMENT.

In order to run this code, you also need to git clone the Greengrass SDK in your local Lambda function.
```
	cd formation_cf_script
	git clone https://github.com/aws/aws-greengrass-core-sdk-python.git
	cp -r aws-greengrass-core-sdk-python/greengrasssdk formation_cf_script/jetson_app_deploy_with_iot

```

### Step 2: Understand deploy.sh script
Examine the deploy.sh file. This is the starting point of the cloud formation. 
This bash script first creates a S3 bucket, and upload the pre-compiled model \(currently a resnet-10 object detection model from deepstream sample\) in this bucket. 
Within this file, we are also using aws sam to deploy cloudformation templates for us. Within it, we are actually deploying provision-greengrass-cfn.yml cloudformation script.
After Cloudformation runs successfully, we are going to generate S3 pre-signed links the provisioned certificates to be downloaded to Jetson devices (which only last for one day). If those links expire, you will have to run the last 5 lines in deploy.sh again and generate new links.

### Step 3: Understand provision-greengrass.yml script
This is a cloudformation script run by deploy.sh. This script internally calls a one-time lambda function to create two things:
1. Greengrass Core
2. DeepStream App
And provision them with IoT certificates. Then download certificates to the designated S3 bucket <YOUR-S3-BUCKET> with name similar to "greengrass-deepstream-$AWS_ACCOUNT_ID-$ENVIRONMENT-assets".

### Step 4:
Run the scripts:
```
	source deploy.env
	. deploy
```
After this, this file should generate and output.txt file in this folder. Just leave it there.
You can also navigate to AWS console, and see things just created in Manage -> Things.

=============

## Part 2: Greengrass Core formation
### Step 3: Understand YAML script for cloudformation
The major function for this script is to create a greengrass group. And to this greengrass group, we attach 6 modules:
- Greengrass Core: a thing with certificates that helps this Greengrass group to connect to cloud MQTT server securely
- Local Lambda function: we use this lambda function to run Deepstream within as a subprocess. We make this function long-live, and run in no-container mode.
- Greengrass Device: this is a separated thing with a different set of certs other than Greengrass Core. This set of certs is directly granted to Deepsteam app, so that Deepstream app can make secure connection with Greengrass Core, which is a local MQTT server
- Greengrass MachineLearning Resource: in this case, this resource is the resnet-10 model we uploaded in S3 in our deploy.sh file. It could also be coming directly from Sagemaker, or uploaded to S3 from other sources.
- Greengrass Subscriptions: we configure command messages to be published by cloud and subscribed by Deepstream app. And we configure performance update messages to be published from Deepstream app and subsribed by cloud. We can theoretically configure any publisher or subscribers based on our need, as long as they have the right credentials to communicate with MQTT server.

This link posts more detailed information on this set-up: https://aws.amazon.com/blogs/iot/automating-aws-iot-greengrass-setup-with-aws-cloudformation/

### Step 4: Configure and deploy the cloud formation script
For this demonstration, we are using sample DeepStream App developed by NVIDIA in their DeepStream. Within the Lambda function to be deployed, there is a compiled executable of sample DeepStream App and its config file. Within the config file, make sure you configure the source and sink correctly, so it can run on your Jetson device smoothly.

You can now cd into this formation_cf_script and run:
```
	source deploy.env
	. deploy
```

=============

## Part 3: Deploy Greengrass on Jetson devices
### Step 5: Set up device

Take out your jetson device, and install Greengrass following this link below (only module 1):
https://docs.aws.amazon.com/greengrass/latest/developerguide/setup-filter.other.html

### Step 6: Download Greengrass Core
https://docs.aws.amazon.com/greengrass/latest/developerguide/what-is-gg.html#gg-core-download-tab
Makesure you download Armv8 (AArch64) version for any Jetson devices. And run the following command in your download path to install:
```
sudo tar -xzvf greengrass-OS-architecture-1.10.0.tar.gz -C /
```

### Step 6: Give ggc_user sudo permission without password
```
sudo visudo
```
Then append the following line to the bottom of the file.
```
$gcc_user ALL=(ALL) NOPASSWD: ALL
```

### Step 7: Set up and run Greengrass on Jetson device
Copy output.txt into jetson device. and run
```
mkdir <DEEPSTREAM_SDK_PATH>/sources/libs/aws_protocol_adaptor/device_client/certs
wget -O /greengrass/certs/certificatePem.cert.pem <LINE0_in_output.txt>
wget -O /greengrass/certs/privateKey.private.key  <LINE1_in_output.txt>
wget -O /greengrass/config/config.json 			  <LINE2_in_output.txt>
wget -O <DEEPSTREAM_SDK_PATH>/sources/libs/aws_protocol_adaptor/device_client/certs/certificatePem.cert.pem <LINE3_in_output.txt>
wget -O <DEEPSTREAM_SDK_PATH>/sources/libs/aws_protocol_adaptor/device_client/certs/privateKey.private.key  <LINE4_in_output.txt>
```
You should now have all the certs and configs needed to run Greengrass, so we can start Greengrass.
```
cd /greengrass/ggc/core
./greengrass start
```

### Step 8: Deploy model to edge
Log into your AWS console, go to the Greengrass group we created, and in Action, click on "Deploy".
## License

This library is licensed under the MIT-0 License. See the LICENSE file.

