# README

## Overview

This is the DKFZ seqware workflow which hosts and calls several workflows:
* DKFZ SNV Calling
* DKFZ Indel Calling
* DKFZ Copy number estimation

All workflows themselves are implemented in such a way that they use SGE directly to run their jobs.

All workflows basically rely on two merged bam (control and tumor sample) files as input files. In addition, the copy number estimation workflow needs input files from EMBL's delly workflow.

## Workflow output

### DKFZ SNV Calling

### DKFZ Indel Calling

### DKFZ Copy number estimation

## Dependencies

To keep the seqware bundle small, it contains only some dependencies. Most dependencies are within a tarball in the GNOS repository. Some additional software needs to be installed before running the workflow.

### System Installs

    sudo apt-get -y install procmail 

## Building the Workflow

Use 
	mvn clean install 
to compile the workflow.

## Authors

* Michael Heinold <m.heinold@dkfz.de>
* Florian Kärcher <f.kaercher@dkfz.de>
