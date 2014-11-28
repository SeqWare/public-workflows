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

## Debugging Roddy

        So starting with an execution directory:
        seqware@master:/datastore/testdata/DKFZ-PID0/roddyExecutionStore/exec_141110_102343137_seqware_snvCalling
        The structure is basically [Dataset]/[roddyExecutionStore]/[date_time_user_workflow]
        
        In that directory you will find, i.e.:
        analysisTools   								<- Here all the tools are stored / linked
        executedJobs.txt   								<- This is an xml file containing all started jobs with a lot of additional information
        jobStateLogfile.txt								<- If a job was started or finished an entry is put in here. 574... means start, 0 good, everything else is bad.
        r141110_102343137_DKFZ-PID0_snvAnnotation.o202  <- A log file. Basically a wrapped shell script with the set -xuv / set -o pipefail options
        r141110_102343137_DKFZ-PID0_snvCalling.o177
        [...]
        r141110_102343137_DKFZ-PID0_snvCalling.o200
        r141110_102343137_DKFZ-PID0_snvJoinVcfFiles.o201
        realJobCalls.txt								<- The job ids and the command line calls for qsub jobs.
        repeatableJobCalls.sh							<- Ignore this for the moment.
        runtimeConfig.sh								<- The configuration file used for execution.
        runtimeConfig.xml								<- Same in xml, not valid now.
        temp											<- A directory for debugging, temporary files and other things.
        
        Result files are in here:
        [Dataset]/[analysis result folder]/[files], like i.e.
        DKFZ-PID0/mpileup/snvs_[PID].vcf.gz

## Authors

* Michael Heinold <m.heinold@dkfz.de>
* Florian Kärcher <f.kaercher@dkfz.de>

## TODO

* the handling of output_prefix is not flexible, want working dir to be the current dir and a system wide folder for resources downloaded only once.
