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

The process below shows you how to run the workflow with custom inputs and
settings vs. the hard-coded test data that comes bundled with the workflow
above.

### Important Config INI Parameters

The following are important parameters that you will need/want to change if you
are running the workflow for real:

#### Skipping Uploads

    skip_upload=true

This parameter controls whether or not the results of the workflow are uploaded
back into GNOS. For testing this defaults to "true" but you can switch it to
"false" and this will upload the workflow results at the end of the workflow.

#### GNOS Input File URLs

    gnos_input_file_urls=https://gtrepo-ebi.annailabs.com/cghub/data/analysis/download/9c414428-9446-11e3-86c1-ab5c73f0e08b,https://gtrepo-ebi.annailabs.com/cghub/data/analysis/download/4fb18a5a-9504-11e3-8d90-d1f1d69ccc24

This is a comma-seperated list of GNOS download URLs.  Each represents one or
more BAM file (assuming unaligned BAM) that will be downloaded by GeneTorrent
and aligned with the workflow.  You get these URLs by either 1) using the
cgquery tool manually to search the GNOS repository which will display the URLs
in the reports it generates or 2) using the workflow decider that will query
GNOS, digest the information, and create the workflow.ini for you.  The latter
approach is a lot easier.

#### GNOS Input Metadata URLs

    gnos_input_metadata_urls=https://gtrepo-ebi.annailabs.com/cghub/metadata/analysisFull/9c414428-9446-11e3-86c1-ab5c73f0e08b,https://gtrepo-ebi.annailabs.com/cghub/metadata/analysisFull/4fb18a5a-9504-11e3-8d90-d1f1d69ccc24

This compliments the input file URLs above with the metadata for each analysis
event.  You should use the same order as the download URLs above.  Like the
download URLs, these URLs are taken from either cgquery results or the decider
will find these for you. They are used by the workflow to pull back needed
metadata for the input samples.

#### GNOS BAM Files

    input_bam_paths=9c414428-9446-11e3-86c1-ab5c73f0e08b/hg19.chr22.5x.normal.bam,4fb18a5a-9504-11e3-8d90-d1f1d69ccc24/hg19.chr22.5x.normal2.bam

The metadata includes information about the BAM files available for each
sample. This lists the BAM files that will be produced as a result of
downloading from the input file URLs. You can get this list of files from the
input metadata either using cgquery or the workflow decider.

#### GNOS Key

    gnos_key=\${workflow_bundle_dir}/Workflow_Bundle_\${workflow-directory-name}/\${version}/scripts/gnostest.pem

They key is used for communicating with GNOS for both download and upload.  You
need to apply for a key since access to GNOS for PanCancer is controlled.  See
https://pancancer-token.annailabs.com/ for getting this key.

#### GNOS Server URL

    gnos_output_file_url=https://gtrepo-ebi.annailabs.com

This is the URL for the GNOS server, used for the validation and upload of
result data when the workflow finishes.

### Running with Custom Settings File

You can make your own ini file based on the information above and the sample
\${workflow_bundle_dir}/Workflow_Bundle_\${workflow-directory-name}/\${version}/config/workflow.ini
in and feed that to the workflow.

    $ seqware bundle launch --dir ~/provisioned_bundles/Workflow_Bundle_BWA_2.1_SeqWare_1.0.11 --ini-file my_settings.ini

This will launch the workflow with your custom settings.

## Next Steps

Take a look at the "BWA-Mem Automated Workflow Running SOP", that will give you
information on using the decider which is a script that queries GNOS and
prepares the workflow.ini.  This makes the whole process of parameterizing the
workflow way easier than manually parameterizing the above.
