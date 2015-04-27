# The DKFZ/EMBL PanCancer Variant Calling Workflow

This is intended to wrap the DKFZ and EMBL workflows as a SeqWare workflow and allow it to run on the SeqWare Docker container.  It is the orchestration workflow that calls GNOS download, the EMBL workflow for structural variation, the DKFZ workflow for SNVs, indels, and copy number, and finally upload of results back to GNOS.

Unlike previous workflows, there is now a central decider that generates INIs from a de-duplicated central index hosted on PanCancer.info.  This should be much more reliable than the distributed deciders used previously.  For more information see the [central-decider-client](https://github.com/ICGC-TCGA-PanCancer/central-decider-client).

[![Build Status](https://travis-ci.org/SeqWare/public-workflows.svg?branch=develop)](https://travis-ci.org/SeqWare/public-workflows)

## Users

In order to get this running, you will need to setup Docker. It is recommended that you do this on an Amazon host with a 100GB root disk (one good choice is ami-9a562df2, this should be an Ubuntu 14.04 image if you use another AMI). We used a m3.xlarge:

        curl -sSL https://get.docker.com/ | sudo sh
        sudo usermod -aG docker ubuntu
        exit

Next, after logging back in, cache the seqware containers that we will be using 

        docker pull seqware/seqware_whitestar
        docker pull seqware/seqware_full
        docker pull pancancer/pcawg-delly-workflow
        
You need to get and build the DKFZ portion:

        git clone git@github.com:SeqWare/docker.git

See https://github.com/SeqWare/docker/tree/develop/dkfz_dockered_workflows for downloading Roddy bundles of data/binaries.

        cd ~/gitroot/docker/dkfz_dockered_workflows/
        # you need to download the Roddy binary, untar/gz, and move the Roddy directory into the current git checkout dir
        docker build -t pancancer/dkfz_dockered_workflows .
        Successfully built 0805f987f138
        # you can list it out using...
        ubuntu@ip-10-169-171-198:~/gitroot/docker/dkfz_dockered_workflows$ docker images
        REPOSITORY                          TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
        pancancer/dkfz_dockered_workflows   latest              0805f987f138        8 seconds ago       1.63 GB

Next, setup your environment with your workflow and a shared datastore directory

        sudo mkdir /workflows && sudo mkdir /datastore
        sudo chown ubuntu:ubuntu /workflows
        sudo chown ubuntu:ubuntu /datastore
        chmod a+wrx /workflows && chmod a+wrx /datastore
        wget https://seqwaremaven.oicr.on.ca/artifactory/seqware-release/com/github/seqware/seqware-distribution/1.1.0/seqware-distribution-1.1.0-full.jar
        sudo apt-get install openjdk-7-jdk maven

Next, you will need to build a copy of the workflow wrappering the DKFZ and EMBL pipelines.

        git clone git clone git@github.com:SeqWare/public-workflows.git
        # git checkout feature/workflow-DKFZ-EMBL-wrap-workflow # TODO: replace with release string
        cd DEWrapperWorkflow/
        mvn clean install
        rsync -rauvL target/Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0 /workflows/

This will eventually be uploaded to S3.

<!--
Do your `mvn clean install`,`seqware bundle package --dir target/Workflow_Bundle_WorkflowOfWorkflows_1.0.0_SeqWare_1.1.0/`, and then scp the bundle in. These next steps assume that you have copied in your bundle. Do the following if you're downloading a zip from S3.

        java -cp seqware-distribution-1.1.0-full.jar net.sourceforge.seqware.pipeline.tools.UnZip --input-zip Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0.zip --output-dir Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0
-->

Copy your pem key to:

        /home/ubuntu/.ssh/20150212_boconnor_gnos_icgc_keyfile.pem

Finally, you can run your workflow with a small launcher script that can be modified for different workflows

        wget https://raw.githubusercontent.com/SeqWare/public-workflows/develop/DEWrapperWorkflow/launchWorkflow.sh
        # edit the above script if you need to
        docker run --rm -h master -t -v /var/run/docker.sock:/var/run/docker.sock -v /datastore:/datastore -v /workflows:/workflows -v `pwd`/launchWorkflow.sh:/launchWorkflow.sh  -i seqware/seqware_full /start.sh "bash /launchWorkflow.sh"        
        
Note that you can also launch using the whitestar workflow engine which is much faster but lacks the more advanced features that are normally present in SeqWare. See [Developing in Partial SeqWare Environments with Whitestar](https://seqware.github.io/docs/6-pipeline/partial_environments/) for details. 

        wget https://raw.githubusercontent.com/SeqWare/public-workflows/develop/DEWrapperWorkflow/launchWorkflowDev.sh
        # edit the above script if you need to
        docker run --rm -h master -t -v /var/run/docker.sock:/var/run/docker.sock -v /datastore:/datastore -v /workflows:/workflows -v `pwd`/launchWorkflowDev.sh:/launchWorkflowDev.sh -i seqware/seqware_whitestar bash /launchWorkflowDev.sh

Look in your datastore for the two working directories generated per run (one for the overall workflow and one for the embedded workflow, currently HelloWorld)

        ls -alhtr /datastore

If you want to run with a specific INI:

        # edit the ini
        vim workflow.ini
        docker run --rm -h master -t -v /var/run/docker.sock:/var/run/docker.sock -v /datastore:/datastore -v /workflows:/workflows -v `pwd`/workflow.ini:/workflow.ini -i seqware/seqware_whitestar bash -c 'seqware bundle launch --dir /workflows/Workflow_Bundle_DEWrapperWorkflow_1.0.0_SeqWare_1.1.0 --engine whitestar --no-metadata --ini /workflow.ini'

This is the approach you would take for running in production.  Each donor gets an INI file that is then used to launch a workflow using Docker.  If you choose to upload to S3 or GNOS your files should be uploaded there.  You can also find output in /datastore.

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
