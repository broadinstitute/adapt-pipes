# adapt-pipes
Workflows to run ADAPT on AWS Batch

## Setting up Cromwell Server for AWS

### Setting up a VPC

1. Go to [AWS CloudFormation](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#), and click "Create Stack". If prompted, click "With new resources (standard)".

2. Choose "Template is ready" and "Upload a template file". Upload `/cromwell-setup/vpcstack.json`, then hit "Next".

3. Name your stack (ex. `Cromwell-VPC`).

4. Select regions for your availability zones. You must select between 2 and 4 regions. If you are unsure, select `us-east-1a`, `us-east-1b`, `us-east-1c`, and `us-east-1d`. 

5. Select the number of availability zones that matches the number of regions you chose in Step 4.

6. Keep the defaults for the rest of the options on this page, and hit "Next".

7. Add any tags you would like, then hit "Next". Tags will be added to all AWS resources built by the stack and serve as additional metadata.

8. Click "Create Stack".

9. After the stack has finished running, click on the stack name, click on `Outputs`, and record each Private and 
Public Subnet ID (in the form `subnet-#################`) and the VPC ID (in the form `vpc-#################`). You will need them to set up the Genomics Workflow Core and Cromwell Resources.

### Setting up Genomics Workflow Core and Cromwell Resources
1. Open `Installing the Genomics Workflow Core and Cromwell.pdf` in `/cromwell-setup/` and follow the instructions. Whenever it asks to use VPC subnets, use as many as you can from "Setting up a VPC".

2. If there are issues with running the stacks, try replacing "latest" with "v3.0.1" in any S3 file paths.

3. If it still is not working, upload the contents of `/cromwell-setup` to an S3 bucket, and run the stacks using paths to your personal S3 bucket.

4. After the stacks have finished running, click on the core stack name, click on `Outputs`, and record the `DefaultJobQueueArn`, the `PriorityJobQueueArn`, and the `S3BucketName`. You will need these to set up your input files. Then, click on the resources stack name, click on `Outputs`, and record the `HostName`. The `HostName` will be how you connect to your Cromwell Server.

## Running ADAPT on Cromwell and AWS Batch

### Setting up ADAPT Docker images
You may either use our Docker images or create your own. If you would like to use our Docker images, use `194065838422.dkr.ecr.us-east-1.amazonaws.com/adaptcloud` to use cloud memoization features. Otherwise, or if you're unsure, use `194065838422.dkr.ecr.us-east-1.amazonaws.com/adapt`. 

If you would like to build your own Docker images, do the following:

1. Install [Docker](https://docs.docker.com/get-docker/) and [Git](https://git-scm.com/downloads).

2. Clone the [ADAPT repository](https://github.com/broadinstitute/adapt) to your computer using the following command:
```
$ git clone https://github.com/broadinstitute/adapt.git
```

3. Go into the repository, and build the ADAPT docker image using the following commands:
```
$ cd adapt
$ docker build . -t adapt
```

4. If you would like to use cloud memoization features, also run the following command:
```
$ docker build . -t adaptcloud -f ./cloud.Dockerfile
```

If you are building your own Docker image, you will also need to publish it. You can do this either via DockerHub or via AWS itself. The following are instructions of how to publish your image using AWS.

1. Install the [AWS Command Line Interface](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html).

2. Open [AWS Elastic Cloud Repository (ECR)](https://console.aws.amazon.com/ecr/repositories).

3. Click "Create Repository".

4. Name your repository, keep the other options at their defaults, and click "Create Repository".

5. Click on your repository's name, click "View push commands", and then follow the instructions listed there to push your Docker image to AWS.

6. Click back to the ECR home screen, and record the URI of your image.

### Setting up Input Files

To send the job to your Cromwell server, you will need two or three files locally:

1. a WDL workflow for ADAPT.
To design for a single taxon, use `single_adapt.wdl`. To design for multiple taxa in parallel, use `parallel_adapt.wdl`.

2. a JSON file of inputs to your WDL
To design for a single taxon, modify `single_adapt_input_template.json`. To design for multiple taxa in parallel, modify `parallel_adapt_input_template.json`.
For `single_adapt_input_template.json`, if you would like to be specific against any taxa, you will need to upload a tab-separated value file (TSV) of those taxa to an S3 bucket. The TSV should have a header line with 'family', 'genus', 'species', 'taxid', 'segment', 'refseqs', and 'neighbor-count'.
For `single_adapt_input_template.json`, you will need to upload a tab-separated value file (TSV) of taxa to design for to an S3 bucket. If you would like to be specific against a different set of taxa, you will need to upload another TSV of those taxa. Both TSVs should have a header line with 'family', 'genus', 'species', 'taxid', 'segment', 'refseqs', and 'neighbor-count'. 

3. a configuration file for AWS (optional, only necessary for running workflows through a Cromwell call)
Modify anything that says `REGION`, `S3BUCKET`, and `QUEUEARN` in `aws-template.conf`. 
`REGION` should be the region in which your S3 bucket is stored and your job queues are. You should see something like `us-east-1` in the `DefaultJobQueueArn`/`PriorityJobQueueArn` you recorded in Step 4 of "Setting up Genomics Workflow Core and Cromwell Resources".
`S3BUCKET` should be the `S3BucketName` you recorded in Step 4 of "Setting up Genomics Workflow Core and Cromwell Resources".
`QUEUEARN` should be either the `DefaultJobQueueArn` or the `PriorityJobQueueArn` you recorded in Step 4 of "Setting up Genomics Workflow Core and Cromwell Resources". The `DefaultJobQueueArn` uses Spot instances if capacity is available, then On Demand instances; the `PriorityJobQueueArn` uses On Demand instances until a limit is reached , at which point it will use Spot instances. The `DefaultJobQueueArn` costs less, but the `PriorityJobQueueArn` will work faster.

### Sending Workflow to Cromwell server
There are three methods to run a workflow on your Cromwell Server-either through the Swagger UI, through an HTTP POST command, or through a Cromwell call. 

#### Running your workflow through the Swagger UI

To access the Swagger UI, go to the `HostName` URL you recorded in Step 4 of "Setting up Genomics Workflow Core and Cromwell Resources" in any web browser. 

To run your workflow, click `POST /api/workflows/{version}`, click "Try it Out", set `version` to "v1", upload your WDL workflow to `workflowSource`, upload your JSON input file to `workflowInputs`, set `workflowType` to "WDL", set `workflowTypeVersion` to "1.0", and click "Execute". Record the workflow ID outputted.

To check the status of your workflow, click `GET /api/workflows/{version}/{id}/status`, click "Try it Out", set `version` to "v1", set `id` to the workflow ID previously outputted, and click "Execute".

To get the outputs of your workflow once it has finished running, click `GET /api/workflows/{version}/{id}/outputs`, click "Try it Out", set `version` to "v1", set `id` to the workflow ID previously outputted, and click "Execute". You will get S3 paths to the files containing your outputs, which you can access via the [S3 dashboard](https://s3.console.aws.amazon.com/s3/home).

You may keep track of the status of each job produced by the workflow by referring to the [AWS Batch Dashboard](https://console.aws.amazon.com/batch/v2/home). 

#### Running your workflow through an HTTP POST command

To run your workflow, open a terminal, and run the following command:
```
$ curl -k -X POST "https://{HostName}/api/workflows/v1" \
	-H "accept: application/json" \
	-F "workflowSource=@{WDL Workflow}"
	-F "workflowInputs=@{JSON Inputs}"
```

To check the status of your workflow, run the following command:
```
$ curl -k -X GET "https://{HostName}/api/workflows/v1/{id}/status
```

To get the outputs of your workflow once it has finished running, run the following command:
```
$ curl -k -X GET "https://{HostName}/api/workflows/v1/{id}/outputs
```
You will get S3 paths to the files containing your outputs, which you can access via the [S3 dashboard](https://s3.console.aws.amazon.com/s3/home). 

You may keep track of the status of each job produced by the workflow by referring to the [AWS Batch Dashboard](https://console.aws.amazon.com/batch/v2/home).

#### Running your workflow through a Cromwell call

First, you will need to download [Cromwell](https://github.com/broadinstitute/cromwell/releases/tag/53.1). You will only need to download `cromwell-53.1.jar`.

To run your workflow, open a terminal, and run the following command:
```
$ java -Dconfig.file={AWS Configuration file} -jar {path to Cromwell jar file} run {WDL Workflow} -i {JSON Inputs}
```

You will get updates on the status of your workflow in the terminal, as well as the S3 paths to the files of your outputs. You can access these via the [S3 dashboard](https://s3.console.aws.amazon.com/s3/home). 
