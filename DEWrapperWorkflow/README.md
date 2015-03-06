This is a prototype for the DKFZ/EMBL workflow. 

This is intended to wrap the DKFZ and EMBL workflows as a SeqWare workflow and allow it to run on both within a seqware/seqware\_full container and on our existing Bindle provisioned infrastructure with an additional Docker install. 

[![Build Status](https://travis-ci.org/SeqWare/public-workflows.svg?branch=feature%2Fworkflow-DKFZ-EMBL-wrap-workflow)](https://travis-ci.org/SeqWare/public-workflows)

## Users

In order to get this running, you will need to setup Docker. It is recommended that you do this on an Amazon host with a 100GB root disk (one good choice is ami-9a562df2). We used a m3.xlarge:

        curl -sSL https://get.docker.com/ | sudo sh
        sudo usermod -aG docker ubuntu
        exit

Next, after logging back in, cache the seqware containers that we will be using 

        docker pull seqware/seqware_whitestar
        docker pull seqware/seqware_full

Next, setup your environment with your workflow and a shared datastore directory

        sudo mkdir /workflows && sudo mkdir /datastore
        sudo chown ubuntu:ubuntu /workflows
        sudo chown ubuntu:ubuntu /datastore
        chmod a+wrx /workflows && chmod a+wrx /datastore
        wget https://seqwaremaven.oicr.on.ca/artifactory/seqware-release/com/github/seqware/seqware-distribution/1.1.0-alpha.6/seqware-distribution-1.1.0-alpha.6-full.jar
        sudo apt-get install openjdk-7-jre-headless

Next, you will need to grab a copy of your workflow. Do your `mvn clean install`,`seqware bundle package --dir target/Workflow_Bundle_WorkflowOfWorkflows_1.0-SNAPSHOT_SeqWare_1.1.0-rc.1/`, and then scp the bundle in. These next steps assume that you have copied in your bundle. Do 

        java -cp seqware-distribution-1.1.0-alpha.6-full.jar net.sourceforge.seqware.pipeline.tools.UnZip --input-zip Workflow_Bundle_DEWrapperWorkflow_1.0-SNAPSHOT_SeqWare_1.1.0-rc.1.zip --output-dir Workflow_Bundle_DEWrapperWorkflow_1.0-SNAPSHOT_SeqWare_1.1.0-rc.1

Finally, you can run your workflow with a small launcher script that can be modified for different workflows

        wget https://raw.githubusercontent.com/SeqWare/public-workflows/feature/workflow-DKFZ-EMBL-wrap-workflow/DEWrapperWorkflow/launchWorkflow.sh
        docker run --rm -h master -t -v /var/run/docker.sock:/var/run/docker.sock -v /datastore:/datastore -v /workflows:/workflows -v `pwd`/launchWorkflow.sh:/launchWorkflow.sh  -i seqware/seqware_full /start.sh "bash /launchWorkflow.sh"        

Look in your datastore for the two working directories generated per run (one for the overall workflow and one for the embedded workflow, currently HelloWorld)

        ls -alhtr /datastore

## Developers

Refer to https://github.com/SeqWare/docker/commit/9b98f6ec47f0acc4545fd0d6243a7693305da83a to see the Perl script this was derived from. 

These are the remaining tasks that need to be completed for phase 1

- [ ] uncomment and test the download of data provided with a valid pem key 
- [ ] insert a proper workflow in-place of the HelloWorld bundle that stands in for EMBL
- [ ] uncomment and test upload of EMBL data
- [ ] validate that ini file for DKFZ which looks incomplete
- [ ] replace call to Ubuntu container with a call to the DKFZ container
- [ ] uncomment and test upload of DKFZ data
- [ ] nail down container versions and tag them in Docker Hub (where possible)

Tasks for phase 2

- [ ] Integrate the q2seqware component into the workflow so it can grab an ini and parameterize itself when launching
- [ ] Send tracking information (possibly a scrape of the working directory) back to a reporting queue for debugging and tracking of issues
