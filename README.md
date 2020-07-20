## AWS IoT Greengrass Deploying NVIDIA DeepStream on Edge
This is the cloudformation package to demonstrate Machine Learning model deployment at scale with AWS Greengrass on NVIDIA Jetson Devices. This demonstrates consists four parts:
1. Create IoT Things and attach certificates for Greengrass core thing and DeepStream app thing, which will later be attached to this Greengrass group
2. Simulate a DeepStream package to be deployed by Greengrass
3. Create a Greengrass core with modules attached on AWS Cloud
4. Deploy Greengrass on edge device and run DeepStream App
Please follow the steps below to go through the Cloudformation Example:

## Pre-requisites
1. Be an AWS account admin user
2. Jetson device (this should work for all of the devices in Jetson family) and its sudo access
3. AWS CLI version2 and AWS SAM CLI installed on your computer
   - To install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
   - To install AWS SAM CLI: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html


## Part 1: Create things on AWS IoT (Your PC)
### Step 1: Clone repo and configure environment
If you have not done so, configure your AWS CLI with a profile linked to your account.
```
aws configure --profile ANY_NAME_YOU_LIKE
```

Next, please clone this repo onto any PATH onto your machine.
```
git clone https://github.com/rvanderwerf/aws-iot-greengrass-deploy-nvidia-deepstream-on-edge.git
cd aws-iot-greengrass-deploy-nvidia-deepstream-on-edge
```

Once you successfully cloned this repo, please edit deploy.env file to replace <ANY_NAME_YOU_LIKE> to the profile name you just created above. You can also edit AWS_REGION and ENVIRONMENT. Run the following command after you have modified deploy.env with your aws profile name:
```
source deploy.env
```

Then, we are going to use the contents in provisioning_cf_script folder.
```
cd provisioning_cf_script
```

### Step 2: Understand deploy.sh script
Examine the deploy.sh file. This is the starting point of the cloud formation.
This bash script first creates a S3 bucket to store all of the relevant assets created in this repo. Then, it
calls provision-greengrass-cfn.yml CloudFormation script with AWS SAM CLI toolset.

After CloudFormation runs successfully, we are going to generate several commands with S3 pre-signed links the provisioned certificates to be downloaded to Jetson devices (which only last for one day) into install_greengrass.sh file, which we are going to use later. The pre-signed links last for a week. If those links expire, you will have to manually run the last 5 lines in deploy.sh again and generate new links.

### Step 3: Understand provision-greengrass.yml script
This is a CloudFormation script run by deploy.sh. This script internally calls a one-time lambda function to create two things:
1. Greengrass Core
2. DeepStream App
And provision them with IoT certificates. Then download certificates to the designated S3 bucket <YOUR-S3-BUCKET> with name similar to "greengrass-deepstream-$AWS_ACCOUNT_ID-$ENVIRONMENT-assets".

### Step 4:
Run the provisioning script:
```
. deploy.sh
```
After this, an output.txt file should be generated in this folder. Just leave it there.
You can also navigate to AWS console, and see things just created in Manage -> Things.


## Part 2: Simulate a deployment package (Still on your PC)
### Step 5: Upload trained ML model to an S3 bucket
We are going to simulate a package to be deployed from AWS cloud to Jetson device by using example applications and models from DeepStream SDK. We can first download DeepStream SDK for Jetson onto this machine from https://developer.nvidia.com/deepstream-download, and download the .tar version. After successful download, you can untar the package:

```
mkdir $GG_DEPLOYMENT_HOME/deepstream-source
tar -xpvf <DOWNLOAD_PATH>/deepstream_sdk_<VERSION>_jetson.tbz2 -C $GG_DEPLOYMENT_HOME/deepstream-source
```

Then, we are going to upload this model into the S3 bucket we created in Part 1.
```
cd $GG_DEPLOYMENT_HOME/deepstream-source/opt/nvidia/deepstream/deepstream-5.0/samples/models/Primary_Detector
zip model.zip *
aws s3 cp ./model.zip s3://$S3_BUCKET/model/model.zip --profile $AWS_PROFILE
```

### Step 5.5: Install DeepStream onto Jetson (If not installed)
If you do not have DeepStream installed, such as running a Jetson Nano SD JetPack 4.4 Image, copy the DeepStream SDK to your device:
```
scp <DOWNLOAD_PATH>/deepstream_sdk_<VERSION>_jetson.tbz2 <YOUR_JETSON_USERNAME>@<YOUR_JETSON_IP>:/home/<USER_HOME>

```
Now ssh do your Jetson device and install the SDK
```
cd /
sudo tar xpvf <DOWNLOAD_PATH>/deepstream_sdk_<VERSION>_jetson.tbz2
```
### Step 6: Prepare DeepStream Application to be deployed
Once we upload the model, we also need to prepare a DeepStream package to be deployed with Greengrass. We are going to use DeepStream sample app on your Jetson device for this demonstration:
```
scp <YOUR_JETSON_USERNAME>@<YOUR_JETSON_IP>:<ABSOLUTE_DEEPSTREAM_PATH>/sources/apps/sample_apps/deepstream-app/* $GG_DEPLOYMENT_HOME/formation_cf_script/lambda_deepstream_app/
```

### Step 7: Prepare corresponding configuration files for DeepStream Application
Then we need to copy the configuration files to this sample application, and modify it with PLACEHOLDERS so we can locate the ML model correctly when the DeepStream app starts to run in Greengrass:
```
cp $GG_DEPLOYMENT_HOME/deepstream-source/opt/nvidia/deepstream/deepstream-5.0/samples/configs/deepstream-app/config_infer_primary_nano.txt $GG_DEPLOYMENT_HOME/formation_cf_script/lambda_deepstream_app/
cp $GG_DEPLOYMENT_HOME/deepstream-source/opt/nvidia/deepstream/deepstream-5.0/samples/configs/deepstream-app/source1_usb_dec_infer_resnet_int8.txt $GG_DEPLOYMENT_HOME/formation_cf_script/lambda_deepstream_app/
cd $GG_DEPLOYMENT_HOME/formation_cf_script/lambda_deepstream_app
### On MacOS/BSD
sed -i '.tmp' -e 's|model-engine-file|#model-engine-file|g' config_infer_primary_nano.txt
sed -i '.tmp' -e 's|../../models/Primary_Detector_Nano|/resnet_10_model|g' config_infer_primary_nano.txt
sed -i '.tmp' -e 's|model-engine-file|#model-engine-file|g' source1_usb_dec_infer_resnet_int8.txt
### On Ubuntu/Debian
sed -i -e 's|model-engine-file|#model-engine-file|g' config_infer_primary_nano.txt
sed -i -e 's|../../models/Primary_Detector_Nano|/resnet_10_model|g' config_infer_primary_nano.txt
sed -i -e 's|model-engine-file|#model-engine-file|g' source1_usb_dec_infer_resnet_int8.txt

mv config_infer_primary_nano.txt config_infer_primary.txt
## Only needed on MacOS/BSD
rm *.tmp
```

### Step 8: Prepare files/streams to be run by this DeepStream Application
Open the "source1_usb_dec_infer_resnet_int8.txt" you just created in any text editor you prefer. We need to modify the source and sink to the known source. In this demo, we are going to use a RTSP camera as the source. You may also choose to use other sources. So we modify the source to be:
```
[source0]
enable=1
#Type - 1=CameraV4L2 2=URI 3=MultiURI 4=RTSP
type=4
uri=<MY_RTSP_STREAM>
num-sources=1
#drop-frame-interval=2
gpu-id=0
# (0): memtype_device   - Memory type Device
# (1): memtype_pinned   - Memory type Host Pinned
# (2): memtype_unified  - Memory type Unified
cudadec-memtype=0
```

Then we disable any sink except the RTSP stream sink:
```
[sink2]
enable=1
#Type - 1=FakeSink 2=EglSink 3=File 4=RTSPStreaming 5=Overlay
type=4
#1=h264 2=h265
codec=1
sync=0
bitrate=4000000
# set below properties in case of RTSPStreaming
rtsp-port=8554
udp-port=5400
```

If you have other source preference, feel free to use those as well. As long as you verify that your Jetson device have access to these sources or sinks.


### Part 2 Troubleshooting
If you are experiencing error, it is likely that you have switched your terminal and lost environmental variables. In this case, please run locate output.txt in this folder, and copy the last line, which looks similar to: greengrass-deepstream-\<YOUR-AWS-ACCOUNT-NUMBER\>-test-assets. And re-export these environmental variables.

```
source ./deploy.env
```
And then pick up from where you experienced error in the previous commands and try again.

## Part 3: Create Greengrass Group on AWS Cloud
### Step 9: Understand YAML script for cloudformation
The major function for this script is to create a greengrass group. And to this greengrass group, we attach 6 modules:
- Greengrass Core: a thing with certificates that helps this Greengrass group to connect to cloud MQTT server securely
- Local Lambda function: we use this lambda function to run Deepstream within as a subprocess. We make this function long-live, and run Greengrass container mode.
- Greengrass Device: this is a separated thing with a different set of certs other than Greengrass Core. This set of certs is directly granted to Deepsteam app, so that Deepstream app can make secure connection with Greengrass Core, which is a local MQTT server. Please refer to "Extra Note" section for more information on this.
- Greengrass Machine Learning Resource: in this case, this resource is the resnet-10 model we uploaded in S3 manually. It could also be coming directly from Sagemaker, or uploaded to S3 from other sources.
- Other Greengrass Resource: we want to make sure the Greengrass container has all the hardware access within /dev/ repo on Jetson device to run this DeepStream app. The required resource might be different for applications, we need to make sure all of them are attached to the container. Otherwise, it would lead to inference failures.
- Greengrass Subscriptions: we configure command messages to be published by cloud and subscribed by Deepstream app. And we configure performance update messages to be published from Deepstream app and subsribed by cloud. We can theoretically configure any publisher or subscribers based on our need, as long as they have the right credentials to communicate with MQTT server.

This link posts more detailed information on this set-up: https://aws.amazon.com/blogs/iot/automating-aws-iot-greengrass-setup-with-aws-cloudformation/

### Step 10: Install Greengrass Python SDK in local lambda function
In order to use Greengrass lambda function successfully, you also need to git clone the Greengrass SDK in your local Lambda function.
```
cd $GG_DEPLOYMENT_HOME
git clone https://github.com/aws/aws-greengrass-core-sdk-python.git
cp -r aws-greengrass-core-sdk-python/greengrasssdk $GG_DEPLOYMENT_HOME/formation_cf_script/lambda_deepstream_app
```

### Step 11: Form Greengrass group with Cloudformation template
Run the scripts:
```
cd $GG_DEPLOYMENT_HOME/formation_cf_script
. deploy.sh
```
After script runs successfully, you should be able to observe on AWS console a Greengrass group ready to be deployed. And you could click from AWS console to do a deployment on the right upper corner, but don't click deploy yet until Greengrass is set up.

### Part 3 Troubleshooting
If the deployment status shows and yellow label and says "pending", that means the Greengrass group has been successfully created. Otherwise, please click on the deployment failure entry and read the error log.


## Part 4: Install and Start Greengrass on local Jetson device
### Step 12: Set up device
Take out your Jetson device, and install Greengrass by running on your Jetson device install_greengrass.sh script we have prepared for you. In order to copy this script to your Jetson device first, you can either use scp to copy install_greengrass.sh to your Jetson device or upload it somewhere to be downloaded from your Jetson device. And then run
```
scp $GG_DEPLOYMENT_HOME/formation_cf_script/install_greengrass.sh <YOUR_JETSON_USERNAME>@<YOUR_JETSON_IP>:~/Downloads
ssh <YOUR_JETSON_USERNAME>@<YOUR_JETSON_IP>
cd ~/Downloads
sudo sh install_greengrass.sh
```
This script will automatically download and install Greengrass from the following page:
https://docs.aws.amazon.com/greengrass/latest/developerguide/what-is-gg.html#gg-core-download-tab
It will also automatically retrieve the certificates and Greengrass configurations you have created in Part 1 from S3 bucket, and download them on your Jetson device.


You should now have all the resources needed to run DeepStream and Greengrass, so we can start Greengrass. You can now run the following script, and observe the inference result on the sink we just configured.
```
cd /greengrass/ggc/core
sudo ./greengrassd start
```
### Part 4 troubleshooting

If your bucket is not public, you will have noticed some errors during the GG setup. If that's the case, from your PC, copy the bucket contents to your local machine:

cd $GG_DEPLOYMENT_HOME
mkdir s3bucket
aws s3 cp --recursive s3://greengrass-deepstream-XXXX-test-assets .
Now copy the items in the install_greengrass.sh script from your local folder to the correct places on your Jetson device.

If your inference results are not outputted correctly, you can read Greengrass runtime logs to figure out why. Please navigate, on your Jetson device, to the following directory:
```
sudo su
cd /greengrass/ggc/var/log/
```
For Greengrass system logs, you can read log fils in the system folder. For example, "/greengrass/ggc/var/log/system/GGConnManager.log" contains all the messsages Greengrass had received or sent as MQTT broker. "/greengrass/ggc/var/log/system/runtime.log" shows generic Greengrass operation logs.

For Lambda function specific logs, you can locate them in
```
/greengrass/ggc/var/log/user/us-west-2/xxxxxxxxxx
```
where xxxxxxxxxx is you AWS account number. All of the DeepStream operations logs should also be in this folder.

### Extra Note: Run DeepStream IoT Test Applications (test 4 or test 5)
In this application, we also created a separate set of certificates and a corresponding thing for DeepStream app to authenticate with both AWS IoT Core and this Greengrass group. In order to use AWS specific msg-broker in DeepStream, you need to follow this GitHub (but skip provisioning process, because certificates have already been created for you):
https://github.com/awslabs/aws-iot-core-integration-with-nvidia-deepstream

Please use the links in output.txt in this folder to download the certificates to the right folders.


## License

This library is licensed under the MIT-0 License. See the LICENSE file.
