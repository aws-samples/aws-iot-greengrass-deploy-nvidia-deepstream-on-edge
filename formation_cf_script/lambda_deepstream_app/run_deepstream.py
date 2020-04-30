# ##################################################
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.

# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so.
# ##################################################

# When deployed to a Greengrass core, this code will be executed immediately
# as a long-lived lambda function.  The code will enter the infinite while
# loop below.
# If you execute a 'test' on the Lambda Console, this test will fail by
# hitting the execution timeout of three seconds.  This is expected as
# this function never returns a result.
import greengrasssdk
import platform
from threading import Timer
import subprocess
import os
import sys
import logging
logger = logging.getLogger(__name__)
logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)
# Creating a greengrass core sdk client
client = greengrasssdk.client('iot-data')

# Retrieving platform information to send from Greengrass Core
my_platform = platform.platform()
def send_heart_beat():
    client.publish(
        topic='greengrass-deepstream-app/heartbeat',
        payload='Heart beat signal sent from '
                'Greengrass Core running on platform: {}'
                .format(my_platform))
    Timer(60, send_heart_beat).start()
    return


def jetson_deepstream_run():
    send_heart_beat()
    bash_command = "./deepstream-app -c ./source1_usb_dec_infer_resnet_int8.txt"
    process = subprocess.Popen(bash_command.split(), stdout=subprocess.PIPE)
    output, error = process.communicate()
    print(output, error)

# Start executing the function above
jetson_deepstream_run()

# This is a dummy handler and will not be invoked
# Instead the code above will be executed in an infinite loop for our example
def function_handler(event, context):
    return
