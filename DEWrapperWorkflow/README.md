# The DKFZ/EMBL PanCancer Variant Calling Workflow

This is intended to wrap the DKFZ and EMBL workflows as a SeqWare workflow and allow it to run on the SeqWare Docker container.  It is the orchestration workflow that calls GNOS download, the EMBL workflow for structural variation, the DKFZ workflow for SNVs, indels, and copy number, and finally upload of results back to GNOS.

Unlike previous workflows, there is now a central decider that generates INIs from a de-duplicated central index hosted on PanCancer.info.  This should be much more reliable than the distributed deciders used previously.  For more information see the [central-decider-client](https://github.com/ICGC-TCGA-PanCancer/central-decider-client).

[![Build Status](https://travis-ci.org/SeqWare/public-workflows.svg?branch=develop)](https://travis-ci.org/SeqWare/public-workflows)

## Contact

If you have questions please contact Brian O'Connor at boconnor@oicr.on.ca or the PCAWG shepherds list: PCAWG Shepherds <pcawg-shepherds@lists.icgc.org>

## Users

### Worker Host Docker Setup

In order to get this running, you will need to setup Docker on your worker host(s). It is recommended that you do this on an Amazon host with a 1024GB root disk (one good choice is ami-9a562df2, this should be an Ubuntu 14.04 image if you use another AMI). Alternatively, you can use a smaller root disk (say 20G) and then mount an encrypted 1024GB volume on /datastore so analysis is encrypted. We used a r3.8xlarge which has 32 cores and 256G of RAM which is probably too much. A min of 64G is recommended for this workflow so, ideally, you would have 32 cores and 64-128G or RAM:

        curl -sSL https://get.docker.com/ | sudo sh
        sudo usermod -aG docker ubuntu
        # log out then back in!
        exit

### Worker Host Docker Image Pull from DockerHub

Next, after logging back in, cache the seqware containers that we will be using 

        docker pull seqware/seqware_whitestar_pancancer
        docker pull seqware/pancancer_upload_download
        docker pull pancancer/pcawg-delly-workflow
        
### Worker Host Docker Image Build for DKFZ   

#### Option 1 - Download

Note, if you have been given a .tar of the DKFZ workflow you can skip the build below and just import it directly into Docker:

        docker load < dkfz_dockered_workflows_1.0.132-1.tar

#### Option 2 - Build 
        
You need to get and build the DKFZ workflow since we are not allowed to redistribute it on DockerHub:

        git clone https://github.com/SeqWare/docker.git

See the [README](https://github.com/SeqWare/docker/tree/develop/dkfz_dockered_workflows) for how to downloading Roddy bundles of data/binaries and build this Docker image.

        cd ~/gitroot/docker/dkfz_dockered_workflows/
        # you need to download the Roddy binary, untar/gz, and move the Roddy directory into the current git checkout dir
        docker build -t pancancer/dkfz_dockered_workflows .
        Successfully built 0805f987f138
        # you can list it out using...
        ubuntu@ip-10-169-171-198:~/gitroot/docker/dkfz_dockered_workflows$ docker images
        REPOSITORY                          TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
        pancancer/dkfz_dockered_workflows   latest              0805f987f138        8 seconds ago       1.63 GB

### Worker Host Directory Setup

Next, setup your environment with your workflow and a shared datastore directory

        sudo mkdir /workflows && sudo mkdir /datastore
        sudo chown ubuntu:ubuntu /workflows
        sudo chown ubuntu:ubuntu /datastore
        chmod a+wrx /workflows && chmod a+wrx /datastore
        wget https://seqwaremaven.oicr.on.ca/artifactory/seqware-release/com/github/seqware/seqware-distribution/1.1.0/seqware-distribution-1.1.0-full.jar
        sudo apt-get install openjdk-7-jdk maven

### Worker Host DEWrapperWorkflow

#### Option 1 - Download

I uploaded a copy of the .zip for the DEWrapperWorkflow to Amazon S3 to save you the build time.

        wget https://s3.amazonaws.com/oicr.workflow.bundles/released-bundles/Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0.zip
        mkdir /workflows/Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0/
        java -cp seqware-distribution-1.1.0-full.jar net.sourceforge.seqware.pipeline.tools.UnZip --input-zip Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0.zip --output-dir /workflows/Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0/

#### Option 2 - Build 

Next, you will need to build a copy of the workflow wrappering the DKFZ and EMBL pipelines.

        git clone https://github.com/SeqWare/public-workflows.git
        # git checkout feature/workflow-DKFZ-EMBL-wrap-workflow # TODO: replace with release string
        cd DEWrapperWorkflow/
        mvn clean install
        rsync -rauvL target/Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0 /workflows/

### Worker Host GNOS Pem Key

Copy your pem key to:

        /home/ubuntu/.ssh/gnos.pem

### Worker Host Run the Workflow in Test Mode

Now you can launch a test run of the workflow using the whitestar workflow engine which is much faster but lacks the more advanced features that are normally present in SeqWare. See [Developing in Partial SeqWare Environments with Whitestar](https://seqware.github.io/docs/6-pipeline/partial_environments/) for details. 

       docker run --rm -h master -it -v /var/run/docker.sock:/var/run/docker.sock -v /datastore:/datastore -v /workflows:/workflows -v `pwd`/workflow.ini:/workflow.ini -v /home/ubuntu/.ssh/gnos.pem:/home/ubuntu/.ssh/gnos.pem seqware/seqware_whitestar_pancancer /bin/bash -c 'seqware bundle launch --dir /workflows/Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0 --engine whitestar --no-metadata'

Look in your datastore for the oozie-<uuid> working directory created.  This contains the scripts/logs (generated-script directory) and the working directory for the two workflows (shared-data):

        ls -alhtr /datastore

### Worker Host Launch Workflow with New INI File for Real Run

If you want to run with a specific INI:

        # edit the ini
        vim workflow.ini
        docker run --rm -h master -it -v /var/run/docker.sock:/var/run/docker.sock -v /datastore:/datastore -v /workflows:/workflows -v `pwd`/workflow.ini:/workflow.ini -v /home/ubuntu/.ssh/gnos.pem:/home/ubuntu/.ssh/gnos.pem seqware/seqware_whitestar_pancancer bash -c 'seqware bundle launch --dir /workflows/Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0 --engine whitestar --no-metadata --ini /workflow.ini'

This is the approach you would take for running in production.  Each donor gets an INI file that is then used to launch a workflow using Docker.  If you choose to upload to S3 or GNOS your files should be uploaded there.  You can also find output in /datastore.

### Source of INIs

Adam Wright provides instructions here (https://github.com/ICGC-TCGA-PanCancer/central-decider-client/blob/develop/README.md) on using a simple command line tool for generating INIs based on your site's allocation of donors.

You can use Adam's tool for generating many INI files, one per donor, and it takes care of choosing the correct input based on the curation work the OICR team has done.  It's also very fast to run versus or old "decider" that was used previously to make INI files. See the link above for more directions.

### User Tips for Workflow Settings

The INI files let you control many functions of the workflow.  Here are some of the most important and some that are 
useful but difficult to understand.

#### core variables that change per workflow

The INI contains several important variables that change from donor run to donor run.  These include:

        # General Donor Parameters
        donor_id=test_donor
        project_code=test_project
        # Inputs Parameters
        tumourAliquotIds=f393bb07-270c-2c93-e040-11ac0d484533
        tumourAnalysisIds=ef26d046-e88a-4f21-a232-16ccb43637f2
        tumourBams=7723a85b59ebce340fe43fc1df504b35.bam
        controlAnalysisId=1b9215ab-3634-4108-9db7-7e63139ef7e9
        controlBam=8f957ddae66343269cb9b854c02eee2f.bam
        # EMBL Parameters
        EMBL.delly_runID=f393bb07-270c-2c93-e040-11ac0d484533
        EMBL.input_bam_path_tumor=inputs/ef26d046-e88a-4f21-a232-16ccb43637f2
        EMBL.input_bam_path_germ=inputs/1b9215ab-3634-4108-9db7-7e63139ef7e9

#### file modes

There are three file modes for reading and writing: GNOS, local, S3.  Usually people use GNOS for both
reading and writing the files.  But local file mode can be used when files are already downloaded locally or
you want to asynchronously upload later so you just want to prepare an upload for later use.

These variables are set with:

        downloadSource=[GNOS,local,S3]
        uploadDestination=[GNOS,local,S3]

Keep in mind you can mix and match upload and download options here.  For example, you could download from GNOS
and then upload the resulting variant calls to S3.  Currently, you can't set a list of upload destinations so you
can only upload to one location per run of the workflow.

##### "local" file mode

        downloadSource=local
        uploadDestination=local

You can use local file mode for downloaded files. You need to use full paths to the BAM input files.

        tumourBams=<full_path>/7723a85b59ebce340fe43fc1df504b35.bam
        controlBam=<full_path>/8f957ddae66343269cb9b854c02eee2f.bam

The workflow will then symlink these files and continue the workflow.

For uploads, GNOS is still consulted for metadata unless the following parameter is included:

        localXMLMetadataPath=<path_to_directory_with_analysis_xml>

So this is a little complicated, when using local file upload mode (uploadDestination=local) *and* the previous variable is defined
the upload script will use XML files from this directory named data_<analysis_id>.xml.  It will also suppress the
validation and upload of metadata to GNOS from the upload tool.  In this way you can completely work offline.
By default it's simply not defined and, even in local file mode, GNOS will be queried for metadata when localXMLMetadataPath is null. If you
need to work fully offline make sure you pre-download the GNOS XML, put them in this directory, and name them
according to the standard mentioned above.

##### "GNOS" file mode

        downloadSource=GNOS
        uploadDestination=GNOS

This works similarly to other PanCancer workflows where input aligned BAM files are first downloaded from GNOS
and the resulting variant calls are uploaded to GNOS.  The download and upload servers may be different.  For this
option, you want to make sure you use just the BAM file name in the following variables and leave `localXMLMetadataPath`
blank:

        tumourBams=7723a85b59ebce340fe43fc1df504b35.bam
        controlBam=8f957ddae66343269cb9b854c02eee2f.bam

You also most have the GNOS servers for download and upload defined along with the PEM key files.  Note, in its current
form you can download all BAM inputs from one server and upload the results to one server.  Pulling from multiple 
input servers is not yet possible.

        pemFile=/home/ubuntu/.ssh/gnos.pem
        gnosServer=https://gtrepo-ebi.annailabs.com
        uploadServer=https://gtrepo-ebi.annailabs.com
        uploadPemFile=/home/ubuntu/.ssh/gnos.pem

Obviously, the workflow host will need to be able to reach the GNOS servers multiple times in the workflow.

##### "S3" file mode

This is the least tested file mode.  The idea is that you can pre-stage data in S3 and then very quickly
pull inputs into an AWS host for processing.  At the end of the workflow you can then
write the submission tarball prepared for GNOS to S3 so you can latter upload to GNOS in batch.

To activate this mode:

        downloadSource=S3
        uploadDestination=S3

For downloads from S3:

        tumourBamS3Urls=s3://bucket/path/7723a85b59ebce340fe43fc1df504b35.bam
        controlBamS3Url=s3://bucket/path/8f957ddae66343269cb9b854c02eee2f.bam

You then refer to these using a non-full path:

        tumourBams=7723a85b59ebce340fe43fc1df504b35.bam
        controlBam=8f957ddae66343269cb9b854c02eee2f.bam

For uploads, you set the following for an upload path:

        uploadS3BucketPath=s3://bucket/path

And you also need to set your credentials used for both upload and download:

        s3Key=kljsdflkjsdlkfj
        s3SecretKey=lksdfjlsdkjflksdjfkljsd

Obviously, the workflow host will need to be able to reach AWS multiple times in the workflow so it's best to run
the full workflow in AWS if using this option.

#### upload archive tarball

For local file mode the VCF preparation process automatically creates a tarball bundle of the submission files
which is useful for archiving.  Currently, you don't have much control over where or how these tarballs are written,
you will find them in:

        uploadLocalPath=./upload_archive/

which is relative to the working directory's shared_workspace directory.  It's best to not change this because of the
nested nature of docker calling docker.  Instead, for local file mode, harvest the tarball archives from this directory.

The S3 upload mode also transfers the archive file to S3. 

#### testing data

The workflow comes complete with details about a real donor in the EBI GNOS.  So this means you need to provide a 
valid PEM key on the path specified:

        pemFile=/home/ubuntu/.ssh/gnos.pem
        uploadPemFile=/home/ubuntu/.ssh/gnos.pem

It's the same key and set to upload back to EBI under the test study.

        study-refname-override=CGTEST
        
Keep in mind if you use two different keys (say you download and upload to different GNOS repos) then you need
to provide two `-v` options to the `docker run...` of this workflow, each pointing to a different pem path.

#### cleanup options

I recommend you cleanup bam files but not all.  That way your scripts and log files are preserved but you clean up most
space used by a workflow.  Once your system is working well, you should consider turning on the full cleanup, especially
if your worker nodes/VMs are long-lived.  In this case the variant call files left behind will cause the disk to fill up.

        cleanup=false
        cleanupBams=false

## Developer Info

### DKFZ

Code is located at: https://github.com/SeqWare/docker/tree/develop/dkfz_dockered_workflows

You will need to build this one yourself since it cannot currently be distributed on DockerHub.

### EMBL

Original code is: https://bitbucket.org/weischen/pcawg-delly-workflow

Our import for build process is: https://github.com/ICGC-TCGA-PanCancer/pcawg_delly_workflow

There is a SeqWare workflow and Docker image to go with it.  These are built by Travis and DockerHub respectively.

If there are changes on the original BitBucket repo they need to be mirrored to the GitHub repo to they are automatically built.

#### Github Bitbucket Sync

In order to keep the two of these up-to-date:

First, checkout from bitbucket:

    git clone <bitbucket embl repo>
    
Second, add github as a remote to your .gitconfig

    [remote "github"]
    url = git@github.com:ICGC-TCGA-PanCancer/pcawg_delly_workflow.git
    fetch = +refs/heads/*:refs/remotes/github/*
    
Third, pull from bitbucket and push to Github

    git pull origin master
    git push github

## Dependencies

This project uses components from the following projects

* [pcawg_embl_workflow](https://github.com/ICGC-TCGA-PanCancer/pcawg_delly_workflow)
* [pcawg_dkfz_workflow](https://github.com/SeqWare/docker/tree/develop/dkfz_dockered_workflows)
* [genetorrent](https://cghub.ucsc.edu/software/downloads.html)
