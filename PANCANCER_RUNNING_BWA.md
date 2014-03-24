# TCGA/ICGC PanCancer - BWA-Mem Workflow SOP

This is the SOP for running the latest version of the PanCancer BWA-Mem
Workflow version 2.1.

## Overview

This document tells you how to get and run the PanCancer BWA-Mem Workflow built
using SeqWare.  It is used in Phase II of the project to download unaligned
data from GNOS, align the ~2,500 samples worth of whole genome data, and upload
the result back to GNOS.

## Requirements

We assume you have a functioning SeqWare VM or cluster of VMs to successfully
run the BWA-Mem workflow.  If you do not, please see the [TCGA/ICGC PanCancer -
Computational Node/Cluster Launch
SOP](https://github.com/SeqWare/vagrant/blob/feature/brian_pancan_fixes/PANCAN_CLUSTER_LAUNCH_README.md)
which will tell you how to launch a SeqWare node or cluster of nodes.

To complete this SOP you need:

* a SeqWare node or cluster launched with SeqWare-Vagrant 1.1 or later (https://github.com/SeqWare/vagrant)
* a GNOS key for PanCancer ICGC data access, see https://pancancer-token.annailabs.com/

You must have a GNOS key for the workflow below to work.  Its test data is
hosted on the EBI GNOS repository and, while synthetic data, it is protected
under the same strict access control that other ICGC PanCancer data is
protected.

## Log Into SeqWare Host

At this point you want to log in to you SeqWare host.  See the cluster launch SOP for details on this.

## Building the Workflow from Source

You can choose to build the BWA workflow and this might be extremely nice if 1) you want the latest version of the workflow but we have not made a .zip file available yet or 2) you want to modify the workflow or examine the code yourself.  Our code is available on GitHub and the workflow can be built with Maven on any machine but I will assume you will build on your SeqWare node.  Make sure you are logged in and su to the seqware user.

    # checkout the code
    $ git clone git@github.com:SeqWare/public-workflows.git
    $ cd public-workflows
    $ git checkout feature/brian_bwa_pancan_gnos_download
    # build the workflow
    $ cd workflow-bwa-pancancer
    $ mvn clean install

You should now have a target/Workflow* directory, this is the workflow compiled into runnable form.

## Installing the Workflow from a Package

You can download a pre-created Zip file, keep in mind it take a long time to process a 4G zip file:

    $ wget https://s3.amazonaws.com/oicr.workflow.bundles/released-bundles/Workflow_Bundle_BWA_2.1_SeqWare_1.0.11.zip
    $ seqware bundle install --zip Workflow_Bundle_BWA_2.1_SeqWare_1.0.11.zip

## Running the Workflow with Sample Data

You can run the workflow with integrated sample data.  Before you run it, please locate the GNOS test key and replace it with your own.

    $ seqware bundle launch --dir ~/provisioned_bundles/Workflow_Bundle_BWA_2.1_SeqWare_1.0.11

## Running the Workflow with Real Data

You can make your own ini file and feed that to the workflow.

    $ seqware bundle launch --dir ~/provisioned_bundles/Workflow_Bundle_BWA_2.1_SeqWare_1.0.11 --ini-file my_settings.ini

## Next Steps

Take a look at the "BWA-Mem Automated Workflow Running SOP".
