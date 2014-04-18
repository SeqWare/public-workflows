# TCGA/ICGC PanCancer - BWA-Mem Automated Workflow Running SOP

# TODO: 

* .seqware/settings on the launcher host???? Should add a sample to the tarball.  Also, will need to copy it to ~/.seqware/settings otherwise the submit will not work?  Is this true?

## Overview

This document describes how to automate the running of the BWA-Mem SeqWare
workflow for TCGA/ICGC PanCancer. In order to do this you need to have a GNOS
repository to read data and metadata from, one or more SeqWare node/cluster
provisioned with SeqWare-Vagrant on a PanCancer cloud, and the BWA-Mem workflow
installed on those SeqWare nodes/clusters. The general idea is you run the
"decider" documented here on an hourly cron job on your launcher host which
then finds unaligned samples and assigns running of these samples on one of the
SeqWare hosts.

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

## Getting the Decider and Dependencies

We have a release available at:
https://s3.amazonaws.com/oicr.workflow.bundles/released-bundles/decider-bwa-pancancer_1.0.tar.gz

Download and unzip this to your launcher host.

Next, you need to install dependencies for the decider. This assumes you are on Ubuntu 12.04 for your launcher and logged in as the ubuntu user which can perform admin actions using sudo.

    $ sudo apt-get update
    $ sudo apt-get -q -y --force-yes install liblz-dev zlib1g-dev libxml-dom-perl samtools libossp-uuid-perl libjson-perl libxml-libxml-perl libboost-filesystem1.48.0 libboost-program-options1.48.0 libboost-regex1.48.0 libboost-system1.48.0 libicu48 libxerces-c3.1 libxqilla6
    $ wget http://cghub.ucsc.edu/software/downloads/GeneTorrent/3.8.5/genetorrent-common_3.8.5-ubuntu2.91-12.04_amd64.deb
    $ wget http://cghub.ucsc.edu/software/downloads/GeneTorrent/3.8.5/genetorrent-download_3.8.5-ubuntu2.91-12.04_amd64.deb
    $ wget http://cghub.ucsc.edu/software/downloads/GeneTorrent/3.8.5/genetorrent-upload_3.8.5-ubuntu2.91-12.04_amd64.deb
    $ sudo dpkg -i genetorrent-common_3.8.5-ubuntu2.91-12.04_amd64.deb genetorrent-download_3.8.5-ubuntu2.91-12.04_amd64.deb genetorrent-upload_3.8.5-ubuntu2.91-12.04_amd64.deb

You can check to see if everything is correctly installed with:

    $ perl -c workflow_decider.pl

That should produce no errors.

The SeqWare command line tool is also used by the decider.  Install it using the following:

    $ wget https://github.com/SeqWare/seqware/releases/download/1.0.11/seqware
    $ sudo cp seqware /usr/local/bin/
    $ sudo chmod a+x /usr/local/bin/seqware

Java can be installed using:

    $ sudo apt-get install openjdk-7-jdk

## Cluster Setup

You need to setup one or more nodes/clusters that are used for running
workflows and processing data.  These are distinct from the launcher host which
runs the decider documented here.  Launch one or more compute clusters using
the [TCGA/ICGC PanCancer - Computational Node/Cluster Launch
SOP](https://github.com/SeqWare/vagrant/blob/feature/brian_pancan_fixes/PANCAN_CLUSTER_LAUNCH_README.md).

You should use the node/cluster profile that includes the installation of the
BWA-Mem workflow for PanCancer. This will ensure your compute clusters are
ready to go for analysis.  However, there is one extremely important step that
you will need to manually perform on each cluster you setup.  You need to
ensure you first get a GNOS key for the PanCancer project by following
instructures at the [PAWG Researcher
Guide](https://wiki.oicr.on.ca/display/PANCANCER/PAWG+Researcher%27s+Guide).
You then need to take the contents of this key and replace the contents of
"~seqware/provisioned-bundles/Workflow_Bundle_BWA_2.1_SeqWare_1.0.11/Workflow_Bundle_BWA/2.1/scripts/gnostest.pem"
on the master node of each computational cluster you launch. This will ensure
input and output data can be read/written to the GNOS repositories used in the
project.

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
         "workflow_accession": "2",
         "username": "admin@admin.com",
         "password": "admin",
         "webservice": "http://master:8080/SeqWareWebService",
         "host": "master"
       }
    }

As you build new nodes/clusters you will create a "cluster-name-2",
"cluster-name-3" and so on.  You will then replace "master" with the IP address
of the master node for each of you new clusters/nodes. Note that the "host"
parameter is what the host is called that the workflow is being scheduled on.
Given our provisioning process this is almost always "master". Do not use the
IP address here.

Assuming you are using the SeqWare-Vagrant process to build your computational
clusters, you can get the IP addresses of the master nodes under the
--working-dir specified when you launched the node/cluster.  Change directories
to that directory and then to master.  Then execute "vagrant ssh-config".  That
will show you the IP address of master.  For example, if your working directory
is "target-os-cluster-1":

    $ cd target-os-cluster-1/master
    $ vagrant ssh-config

And the result looks like:

    Host master
      HostName 10.0.20.184
      User ubuntu
      Port 22
      UserKnownHostsFile /dev/null
      StrictHostKeyChecking no
      PasswordAuthentication no
      IdentityFile /home/ubuntu/.ssh/oicr-os-1.pem
      IdentitiesOnly yes
      LogLevel FATAL

You can then use this information to fill in your cluster.json config for the
decider.

## Running the Decider in Testing Mode

First, you will want to run the decider in test mode just to see the samples
available in GNOS and their status (aligned or not). You do this on the
launcher host, presumably running in the same cloud as the GNOS instance you
point to (though not neccesarily). This will produce a report that clearly
shows what is available in GNOS, which samples have already been aligned, etc.

    perl workflow_decider.pl --gnos-url https://gtrepo-ebi.annailabs.com --report report.txt --force-run --test 

This will produce a report in "report.txt" for every sample in GNOS along with
sample workflow execution command lines.

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

### Parameters

There are several additional parameters that may be useful:

    USAGE: 'perl workflow_decider.pl --gnos-url <URL> --cluster-json <cluster.json> [--working-dir <working_dir>] [--sample <sample_id>] [--threads <num_threads_bwa_default_8>] [--test] [--ignore-lane-count] [--force-run] [--skip-meta-download] [--report <workflow_decider_report.txt>] [--settings <seqware_settings_file>] [--upload-results]'
    	--gnos-url           a URL for a GNOS server, e.g. https://gtrepo-ebi.annailabs.com
    	--cluster-json       a json file that describes the clusters available to schedule workflows to
    	--working-dir        a place for temporary ini and settings files
    	--sample             to only run a particular sample
    	--threads            number of threads to use for BWA
    	--test               a flag that indicates no workflow should be scheudle, just summary of what would have been run
    	--ignore-lane-count  skip the check that the GNOS XML contains a count of lanes for this sample and the bams count matches
    	--force-run          schedule workflows even if they were previously run/failed/scheduled
    	--skip-meta-download use the previously downloaded XML from GNOS, only useful for testing
    	--report             the report file name
    	--settings           the template seqware settings file
    	--upload-results     a flag indicating the resulting BAM files and metadata should be uploaded to GNOS, default is to not upload!!!

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

## Cloud-Specific Notes

This section describes modifications needed on a per PanCancer cloud basis.

### BioNimbus PDC

This cloud uses a web proxy, the settings for which are stored in environment variables.  This means you need to override these variables when interacting with the local network.  For example, to run the decider on the launcher host you would do:

    http_proxy= perl workflow_decider.pl --test --ignore-lane-count --force-run --cluster-json cluster.json --report bionimbus.log --gnos-url https://gtrepo-osdc.annailabs.com

The "http_proxy=" here disables the proxy settings for just this command.

## TODO

* document how to find the IPs of the master nodes using a command line script
