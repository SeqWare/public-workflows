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

    sudo apt-get update
    sudo apt-get -y install tabix        # for bgzip
    sudo apt-get -y install procmail    # for lockfile
    sudo apt-get -y install zip
    sudo apt-get -y install subversion
    sudo apt-get -y install make cpanminus
    sudo cpanm Math::CDF # no package for ubuntu 12.04?
    # sudo cpanm XML::XPath
    sudo apt-get -y install libxml-xpath-perl
    sudo apt-get -y install python-dev
    sudo apt-get -y install python-pip
    sudo pip install pysam
    sudo apt-get -y install libgfortran3
    sudo apt-get -y install libglu1-mesa-dev
    wget http://ftp.hosteurope.de/mirror/ftp.opensuse.org/distribution/12.2/repo/oss/suse/x86_64/libpng14-14-1.4.11-2.5.1.x86_64.rpm
    sudo apt-get -y install alien
    sudo alien -i libpng14-14-1.4.11-2.5.1.x86_64.rpm
    sudo ln --symbolic /usr/lib64/libpng14.so.14 /usr/lib/libpng14.so.14

## Building the Workflow

Use 

    mvn clean install 

to compile the workflow.

## Authors

* Michael Heinold <m.heinold@dkfz.de>
* Florian Kärcher <f.kaercher@dkfz.de>
