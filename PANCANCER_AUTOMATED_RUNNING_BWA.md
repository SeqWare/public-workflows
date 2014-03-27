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

    perl workflow_decider.pl --gnos-url http://gtrepo-ebi.annailabs.com --report report.txt --force-run --test 

This will produce a report in "report.txt" for every sample in GNOS along with
sample workflow execution command lines.

## Running the Decider for Real Analysis



* running it for real manually
* cron job

more to come

## Dealing with Workflow Failure

more to come

## Dealing with Cluster Failures

more to come

## Monitoring the System

more to come

## Next Steps

more to come
