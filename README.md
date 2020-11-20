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

3. If it still is not working, upload the contents of `/cromwell-setup/cromwell-setup.zip` to an S3 bucket, and run the stacks using paths to your personal S3 bucket.

4. After the stacks have finished running, click on the core stack name, click on `Outputs`, and record the `DefaultJobQueueArn`, the `PriorityJobQueueArn`, and the `S3BucketName`. You will need these to set up your input files. Then, click on the resources stack name, click on `Outputs`, and record the `HostName`. The `HostName` will be how you connect to your Cromwell Server.

## Running ADAPT on Cromwell and AWS Batch

In order to do this, you will need the following values you recorded while building your server. If you didn't record them, they can be found by going to [AWS Cloud Formation](https://console.aws.amazon.com/cloudformation/home) and following the instructions in Step 4 of "Setting up Genomics Workflow Core and Cromwell Resources".

1. `DefaultJobQueueArn` or `PriorityJobQueueArn`: the Batch queue to run your jobs on.
The `DefaultJobQueueArn` uses Spot instances if capacity is available, then On Demand instances; the `PriorityJobQueueArn` uses On Demand instances until a limit is reached , at which point it will use Spot instances. The `DefaultJobQueueArn` costs less, but the `PriorityJobQueueArn` will work faster.
If you do not have access to the Cloud Formation stack and need to find the `DefaultJobQueueArn` or `PriorityJobQueueArn`, go to the [AWS Batch Management Console](https://console.aws.amazon.com/batch/v2/home), click on "Job queues", and look for the queue with "Default" or "Priority" (and likely "Cromwell") in their names. Click on it, and record the ARN (Amazon Resource Name).

2. `S3BucketName`: the S3 Bucket where your Cromwell files are
If you do not have access to the Cloud Formation stack and need to find the `S3BucketName`, go to the [AWS S3 Management Console](https://s3.console.aws.amazon.com/s3/home) and click through the buckets until you find one with a folder called `_gwfcore`. Record this bucket's name.

3. `HostName`: the URL for your server. 
If you do not have access to the Cloud Formation stack and need to find the `HostName`, go to the [AWS EC2 Management Console](https://console.aws.amazon.com/ec2/v2/home), go to your list of instances, and find the one named "cromwell-server" (or something similar). The "Public IPv4 DNS" of this instance is your `HostName`.

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
To design for a single taxon, modify `single_adapt_input_template.json`. Details on each of the inputs are below:
 - single_adapt.adapt.queueArn: Queue ARN (Amazon Resource Name) of the queue you want the jobs to run on. This should be either the `DefaultJobQueueArn` or the `PriorityJobQueueArn`.
 - single_adapt.adapt.taxid: Taxonomic ID of the design to create.
 - single_adapt.adapt.ref_accs: Accession number for sequences for references used by ADAPT for curation; separate multiple with commas.
 - single_adapt.adapt.segment: Segment number of genome to design for; set to 'None' for unsegmented genomes.
 - single_adapt.adapt.obj: Objective (either 'minimize-guides' or 'maximize-activity').
 - single_adapt.adapt.specific: true to be specific against the taxa listed in specificity_taxa, false to not be specific.
 - single_adapt.adapt.image: URI for Docker ADAPT Image to use
 - single_adapt.adapt.specificity_taxa: Optional, only needed if specific is true. AWS S3 path to file that contains a list of taxa to be specific against. Should have no headings, but be a list of taxonomic IDs in the first column and segment numbers in the second column
 - single_adapt.adapt.rand_sample: Optional, take a sample of RAND_SAMPLE sequences from the taxa to design for.
 - single_adapt.adapt.rand_seed: Optional, set ADAPT's random seed to get consistent results across runs.
 - single_adapt.adapt.bucket: Optional, S3 bucket for cloud memoization. May include path to put memo in a subfolder; do not include '\' at the end.
 - single_adapt.adapt.memory: Optional, sets the memory each job uses. Defaults to 2GB. If jobs fail unexpectedly, increase this.
To design for multiple taxa in parallel, modify `parallel_adapt_input_template.json`. Details on each of the inputs are below:
 - parallel_adapt.queueArn: Queue ARN (Amazon Resource Name) of the queue you want the jobs to run on. This should be either the `DefaultJobQueueArn` or the `PriorityJobQueueArn`.
 - parallel_adapt.objs: Array of objective functions to design for; can include any of {"maximize-activity", "minimize-guides"}.
 - parallel_adapt.sps: Array; include "true" in the array to have designs made specific against any other order in the same family that is listed in ALL_TAXA_FILE; include "false" to design nonspecifically.
 - parallel_adapt.taxa_file: AWS S3 path to a TSV file that contains a list of taxa to design for. Headings should be 'family', 'genus', 'species', 'taxid', 'segment', 'refseqs', 'neighbor-count'.
 - parallel_adapt.format_taxa.all_taxa_file: AWS S3 path to a TSV file that contains a list of all taxa to be specific against (note: will only check for specificity within a family). Can be the same file as TAXA_FILE. Headings should be 'family', 'genus', 'species', 'taxid', 'segment', 'refseqs', 'neighbor-count'.
 - parallel_adapt.adapt.image: URI for Docker ADAPT Image to use
 - parallel_adapt.adapt.bucket: Optional, S3 bucket for cloud memoization. May include path to put memo in a subfolder; do not include '/' at the end.
 - parallel_adapt.adapt.memory: Optional, sets the memory each job uses. Defaults to 2GB. If jobs fail unexpectedly, increase this.

3. a configuration file for AWS (optional, only necessary for running workflows through a Cromwell call)
Modify anything that says `REGION`, `S3BUCKET`, or `QUEUEARN` in `aws-template.conf`. 
`REGION` should be the region in which your S3 bucket is stored and your job queues are. You should see something like `us-east-1` in the `DefaultJobQueueArn`/`PriorityJobQueueArn`; this is the region it is in.
`S3BUCKET` should be the `S3BucketName`.
`QUEUEARN` should be either the `DefaultJobQueueArn` or the `PriorityJobQueueArn`.

### Sending Workflow to Cromwell server
There are three methods to run a workflow on your Cromwell Server-either through the Swagger UI, through an HTTP POST command, or through a Cromwell call. 

#### Running your workflow through the Swagger UI

To access the Swagger UI, go to your `HostName` URL in any web browser. 

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
