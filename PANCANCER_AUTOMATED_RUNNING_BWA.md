# TCGA/ICGC PanCancer - BWA-Mem Automated Workflow Running SOP

## Overview

This document describes how to automate the running of the BWA-Mem SeqWare
workflow for TCGA/ICGC PanCancer. In order to do this you need to have a GNOS
repository to read data and metadata from, one or more SeqWare node/cluster
provisioned with SeqWare-Vagrant on a PanCancer cloud, and the BWA-Mem workflow
installed on those SeqWare nodes/clusters. The general idea is you run the
"decider" documented here on an hourly cron job on your launcher host which
then finds unaligned samples and assigns running of these samples on one of the
SeqWare hosts.

The decider is currently released within the BWA-Mem workflow bundle. So the
easiest way to get the decider is to install the bundle. However, for security
reasons, the luancher is typically a bare-bones Ubuntu box.  In this case the
decider can be downloaded and used independently of the workflow bundle:

    wget https://raw.githubusercontent.com/SeqWare/public-workflows/feature/brian_bwa_pancan_gnos_download/workflow-bwa-pancancer/workflow/scripts/workflow_decider.pl

## Requirements

* seqware nodes/clusters, see https://github.com/SeqWare/vagrant, specifically https://github.com/SeqWare/vagrant/blob/feature/brian_pancan_fixes/PANCAN_CLUSTER_LAUNCH_README.md for information about building nodes/clusters for PanCancer
* a cluster.json that describes the clusters (see the sample cluster.json)
* a launcher host to run the decider on, see https://github.com/SeqWare/vagrant/blob/feature/brian_pancan_fixes/PANCAN_CLUSTER_LAUNCH_README.md
* BWA workflow installed on each node/cluster, see https://github.com/SeqWare/public-workflows/blob/feature/brian_bwa_pancan_gnos_download/PANCANCER_RUNNING_BWA.md
* GNOS key installed on each node/cluster, get your key from https://pancancer-token.annailabs.com/ and replace the contents of gnostest.pem
* GNOS repository filled with data that meets our metadata requirements, see https://wiki.oicr.on.ca/display/PANCANCER/PAWG+Researcher%27s+Guide

## Architecture

This automated guide assumes you will use the following architecture:

                      GNOS repo
                          ^
                          |       -> cluster1 -> run workflow BWA-Mem on sample1
    launcher host -> decider cron -> cluster2 -> run workflow BWA-Mem on sample2
                                  -> node3    -> run workflow BWA-Mem on sample3

In this setup, several SeqWare clusters (or nodes) are created using
SeqWare-Vagrant and the template for PanCancer. The BWA-Mem SeqWare workflow is
installed on each cluster/node as part of this process. The launcher host
periodically runs the decider which queries GNOS to find samples that have yet
to be aligned. It then checks each SeqWare cluster/node it knows about to
determine that the alignment is not currently running (or previously failed).
If both criteria are met (not aligned yet, not running/failed) the decider
"schedules" that sample to a cluster/node for running the BWA workflow. The
final step in the worklfow is to upload the results back to GNOS, indicating to
future runs of the decider that this sample is now aligned.

## Running the Decider in Testing Mode

First, you will want to run the decider in test mode just to see the samples
available in GNOS and their status (aligned or not). You do this on the
launcher host, presumably running in the same cloud as the GNOS instance you
point to (though not neccesarily). This will produce a report that clearly
shows what is available in GNOS, which samples have already been aligned, etc.

    perl workflow_decider.pl --gnos-url https://gtrepo-ebi.annailabs.com --report report.txt --force-run --test 

This will produce a report in "report.txt" for every sample in GNOS along with
sample workflow execution command lines.

## Cluster.JSON

This file provides a listing of the available clusters that can be used to
schedule workflows.  You typically setup several clusters/nodes on a given
cloud environment and then use them for many workflow runs over time.  Some
clusters may be retired or killed over time so it is up to the decider caller
to keep the cluster.json describing the clusters available up to date.  Here is
an example of the JSON format used for this file.  If you use the
SeqWare-Vagrant PanCancer profile that installs the BWA-Mem workflow you will
find it installed under SeqWare accession "2".

    {
      "cluster-name-1": {
         "workflow_accession": "1",
         "username": "admin@admin.com",
         "password": "admin",
         "webservice": "http://master:8080/SeqWareWebService",
         "host": "master"
       }
    }

As you build new nodes/clusters you will create a "cluster-name-2",
"cluster-name-3" and so on.  You will then replace "master" with the IP address
of the master node for each of you new clusters/nodes.

## Running the Decider for Real Analysis

You typically want to run the decider to actually trigger analysis via a
workflow in one of two modes:

* running it manually for a given sample, perhaps to force alignment
* or via a cron job that will periodically cause the decider to run

### Manually Calling

You typically will manually call the decider for a single sample, for example,
if you want to force that sample to be re-run in order to test a workflow.
Here is an example of how to specify a particular sample:

    perl workflow_decider.pl --gnos-url https://gtrepo-ebi.annailabs.com --report report.2.txt --force-run --test --skip-meta-download --sample SP2163

And this will just prepare to launch the workflow for sample SP2163.  Note a
couple of things, 1) it does not launch because --test was used, 2) it does not
download metadata again, it uses the cached version from the last run since
--skip-meta-download, and 3) it just does the sample command for SP2163.

### Automatically Calling via Cron

Add the following to your cronjob, running every hour:

    perl workflow_decider.pl --gnos-url https://gtrepo-ebi.annailabs.com --report report.cron.txt

## Dealing with Workflow Failure

Workflow failures can be monitored with the standard SeqWare tools, see
http://seqware.io for information on how to debug workflows.  If a failure
occurs you will need to use --force-run to run the workflow again.

## Dealing with Cluster Failures

Cluster failures can occur and the strategy for dealing with them is to replace
the lost cluster/node and modify the cluster.json.  Upon next execution, the
workflows will be scheduled to the new system.

## Monitoring the System

The system can be monitored with the standard SeqWare tools, see
http://seqware.io for more information.

