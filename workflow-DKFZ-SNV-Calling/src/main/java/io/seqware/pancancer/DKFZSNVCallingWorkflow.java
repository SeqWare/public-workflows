package io.seqware.pancancer;

import net.sourceforge.seqware.pipeline.workflowV2.*;
import net.sourceforge.seqware.pipeline.workflowV2.model.*;
import java.util.*;
import java.util.logging.*;

public class DKFZSNVCallingWorkflow extends AbstractWorkflowDataModel {

    // GENERAL
    // comma-seperated for multiple bam inputs
    ArrayList<String> inputMetadataURLs = new ArrayList<String>();
    // used to download with gtdownload

    String gnosInputMetadataURLs = null;

    String gnosUploadFileURL = null;
    String gnosUploadDir = null;
    String gnosDownloadDir = null;
    String gnosOutputDir = null;
    String alignmentOutputDir = null;
    String mpileupOutputDir = null;

    String gnosKey = null;
    String outputdir = null;
    String outputPrefix = null;

    boolean useGtDownload = true;
    boolean useGtUpload = true;

    // GTDownload
    // each retry is 1 minute
    String gtdownloadRetries = "30";
    String gtdownloadMd5Time = "120";
    String gtdownloadMem = "8";
    String smallJobMemM = "3000";

    String inputFileTumor = null;
    String inputFileNormal = null;
    String inputFileDependencies = null;

    boolean doCleanup = false;
    String pid = "";
    boolean debugmode = false;
    boolean doSNVCalling = false;
    boolean doIndelCalling = false;
    boolean doCopyNumberEstimation = false;

    private String loadProperty(String id, String _default) {
        try {
            String res = getProperty(id);
            return res == null ? _default : res;
        } catch(Exception ex) {
            return _default;
        }
    }

    @Override
    public Map<String, SqwFile> setupFiles() {

        /*
         * This workflow isn't using file provisioning since we're using
         * GeneTorrent. So this method is just being used to setup various
         * variables.
         */
        try {
            outputPrefix = getProperty("output_prefix");
            outputdir = getProperty("output_dir");
            gnosDownloadDir = getProperty("gnos_download_dir");

            alignmentOutputDir = String.format("/%s/%s/%s/alignment", outputPrefix, outputdir, pid);
            mpileupOutputDir = String.format("/%s/%s/%s/mpileup", outputPrefix, outputdir, pid);

            gnosInputMetadataURLs = getProperty("gnos_input_metadata_urls");
            for (String url : gnosInputMetadataURLs.split(",")) {
                inputMetadataURLs.add(url);
            }

            pid = getProperty("pid");

            gnosUploadFileURL = getProperty("gnos_output_file_url");
            gnosKey = getProperty("gnos_key");
            gnosUploadDir = getProperty("gnos_upload_dir");

            inputFileNormal = getProperty("input_file_control");
            inputFileTumor = getProperty("input_file_tumor");
            inputFileDependencies = getProperty("input_file_dependencies");

            doCleanup = "true".equals(getProperty("clean_up"));
            doSNVCalling = "true".equals(getProperty("snv_calling"));
            doIndelCalling = "true".equals(getProperty("indel_calling"));
            doCopyNumberEstimation = "true".equals(getProperty("ace_seq"));

            debugmode = "true".equals(getProperty("debug_mode"));
            if (debugmode) outputdir = "testdata";

            gtdownloadRetries = loadProperty("gtdownloadRetries", gtdownloadRetries);
            gtdownloadMd5Time = loadProperty("gtdownloadMd5time", gtdownloadMd5Time);
            gtdownloadMem = loadProperty("gtdownloadMemG", gtdownloadMem);
            smallJobMemM = loadProperty("smallJobMemM", smallJobMemM);

            useGtDownload = !"false".equals(getProperty("use_gtdownload"));
            useGtUpload = !"false".equals(getProperty("use_gtupload"));

        } catch (Exception e) {
            Logger.getLogger(DKFZSNVCallingWorkflow.class.getName()).log(Level.SEVERE, null, e);
            throw new RuntimeException("Problem parsing variable values: " + e.getMessage());
        }

        return this.getFiles();
    }

    @Override
    public void setupDirectory() { }

    private Job createRoddyJob(String name, String pid, String configuration, List<Job> parentJobs) {
        return createRoddyJob(name, pid, configuration, parentJobs, "run");
    }

    private Job createRoddyJob(String name, String pid, String analysisConfigurationID, List<Job> parentJobs, String runMode) {
        Job job = this.getWorkflow().createBashJob(name);
        for (Job parentJob : parentJobs) {
            job.addParent(parentJob);
        }
        String fullConfiguration = "dkfzPancancerBase" + (debugmode ? ".dbg" : "") + "@" + analysisConfigurationID;
        job.getCommand().addArgument("cd " + this.getWorkflowBaseDir() + "/RoddyBundlePancancer")
                .addArgument(" && bash roddy " + runMode + " " + fullConfiguration + " " + pid)
                .addArgument("--useconfig=applicationPropertiesAllLocal.ini")
                .addArgument("--waitforjobs");
        if (debugmode)
            job.getCommand().addArgument("--verbositylevel=5 ");
        return job;
    }

    private Job createGNOSDownloadJob(String name, String file, String type, String id, Job parent) {
        Job job = this.getWorkflow().createBashJob(name);
        addDownloadJobArgs(job, file, type, id);
        job.setMaxMemory(gtdownloadMem + "000");
        job.addParent(parent);
        return job;
    }

    private Job createGNOSUploadJob(String name, String file, Job parent) {
        Job jobUpload = this.getWorkflow().createBashJob(name);
        addUploadJobArgs(jobUpload, file);
        jobUpload.setMaxMemory(gtdownloadMem + "000");
        jobUpload.addParent(parent);
        return jobUpload;
    }


    @Override
    public void buildWorkflow() {
        boolean runAtLeastOneJob = doSNVCalling & doIndelCalling & doCopyNumberEstimation;

        // the download jobs that either downloads or locates the file on the filesystem
        // download the normal and tumor bamfile and the dependencies jar
        Job jobDownloadTumorBam = null;
        Job jobDownloadControlBam = null;
        Job jobDownloadWorkflowDependencies = null;
        if (runAtLeastOneJob) {
            Job createDirs = this.getWorkflow().createBashJob("CreateDirs");
            createDirs.getCommand()
                    .addArgument("cd /" + outputPrefix)
                    .addArgument("&& mkdir -p " + alignmentOutputDir)
                    .addArgument("&& mkdir -p " + mpileupOutputDir)
                    .addArgument("&& mkdir -p " + gnosDownloadDir)
                    .addArgument("&& mkdir -p " + gnosUploadDir);
            jobDownloadTumorBam = createGNOSDownloadJob("GNOSDownload Tumor", inputFileTumor, "BAM", "tumor", createDirs);
            jobDownloadControlBam = createGNOSDownloadJob("GNOSDownload Normal", inputFileNormal, "BAM", "control", createDirs);
            jobDownloadWorkflowDependencies = createGNOSDownloadJob("GNOSDownload Dependencies", inputFileDependencies, "TAR", "dependencies", createDirs);
        }

        // Creaty job variables
        Job jobSNVCalling = null;
        Job jobIndelCalling = null;
        Job jobCopyNumberEstimationFinal = null;
        if (doSNVCalling) {
            jobSNVCalling = createRoddyJob("Roddy:SNVCalling", pid, "snvCalling", Arrays.asList(jobDownloadControlBam, jobDownloadTumorBam, jobDownloadWorkflowDependencies));
            createGNOSUploadJob("GNOSUpload Raw VCF SNVCalling", "snvs_" + pid + "_raw.vcf.gz", jobSNVCalling);
            createGNOSUploadJob("GNOSUpload VCF SNVCalling", "snvs_" + pid + ".vcf.gz", jobSNVCalling);
        }

        if (doIndelCalling) {
            createRoddyJob("Roddy:IndelCalling", pid, "indelCalling", Arrays.asList(jobDownloadControlBam, jobDownloadTumorBam, jobDownloadWorkflowDependencies));
            createGNOSUploadJob("GNOSUpload Raw VCF IndelCalling", "snvs_" + pid + "_raw.vcf.gz", jobSNVCalling);
            createGNOSUploadJob("GNOSUpload VCF IndelCalling", "snvs_" + pid + ".vcf.gz", jobSNVCalling);
        }

        if (doCopyNumberEstimation) {
            Job jobCopyNumberEstimation = createRoddyJob("Roddy:CNE", pid, "copyNumberEstimation", Arrays.asList(jobDownloadControlBam, jobDownloadTumorBam, jobDownloadWorkflowDependencies));
            createGNOSUploadJob("GNOSUpload VCF", "snvs_" + pid + ".vcf.gz", jobCopyNumberEstimationFinal);
            //TODO Create additional files upload job.
        }


        // CLEANUP DOWNLOADED INPUT BAM FILES (And intermediate files?)
        if (doCleanup) {
            Job cleanup = this.getWorkflow().createBashJob("clean up");
            cleanup.getCommand().addArgument("rm -fr /" + outputPrefix + "/" + outputdir + " ;")
                    .addArgument("rm -fr /" + outputPrefix + "/" + gnosDownloadDir + ";")
                    .addArgument("rm -fr /" + outputPrefix + "/" + gnosUploadDir + " ;");

            cleanup.setMaxMemory(smallJobMemM);

            //If no job was started, then the cleanup can be run without any dependency.
            if(runAtLeastOneJob) {
                if (doSNVCalling) cleanup.addParent(jobSNVCalling);
                if (doIndelCalling) cleanup.addParent(jobIndelCalling);
                if (doCopyNumberEstimation) cleanup.addParent(jobCopyNumberEstimationFinal);
            }
        }
    }

    private Job addDownloadJobArgs(Job job, String fileURL, String filetype, String type) {
        String[] urlElements = fileURL.split("/");
        String dir = urlElements[urlElements.length - 1];
        String gnosOutputDir = String.format("/%s/%s/%s", outputPrefix, gnosDownloadDir, dir);

        job.getCommand()
                .addArgument("perl " + this.getWorkflowBaseDir() + "/scripts/launch_and_monitor_gnos.pl")
                .addArgument("--command 'gtdownload -c " + gnosKey + " -d " + fileURL + " -p /datastore/gnos_download '")
                .addArgument("--file-grep " + dir)
                .addArgument("--search-path .")
                .addArgument("--retries " + gtdownloadRetries)
                .addArgument("--md5-retries " + gtdownloadMd5Time + ";");

        if (filetype.equalsIgnoreCase("BAM")) {
            String bamTumorSrc = String.format("%s/*.bam", gnosOutputDir);
            String baiTumorSrc = bamTumorSrc + ".bai";
            String bamTumorDst = String.format("%s/%s_%s_merged.mdup.bam", alignmentOutputDir, type, pid);
            String baiTumorDst = bamTumorDst + ".bai";
            job.getCommand().addArgument(String.format("ln -sn %s  %s ;", bamTumorSrc, bamTumorDst))
                    .addArgument(String.format("ln -sf %s  %s ;", baiTumorSrc, baiTumorDst));
        }
        if (filetype.equalsIgnoreCase("TAR")) {
            String tarFile = "/" + outputPrefix + "/workflow-dependencies.tar.gz";
            job.getCommand().addArgument("cd /" + outputPrefix + " && if [ ! -d \"bundledFiles\" ]; ")
                    .addArgument(String.format("then  ln -sf  %s/*.tar.gz %s; ", gnosOutputDir, tarFile))
                    .addArgument(String.format("tar -xvf %s  && rm %s; fi", tarFile, tarFile));
        }
        return (job);
    }

    private Job addUploadJobArgs(Job job, String file) {

        job.getCommand()
                .addArgument(String.format(" cd %s && md5sum %s | awk '{printf $1}' > %s.md5 ;", mpileupOutputDir, file, file));

        job.getCommand()
                .addArgument("perl " + this.getWorkflowBaseDir() + "/scripts/gnos_upload_data.pl")
                .addArgument("--bam " + mpileupOutputDir + "/" + file)
                .addArgument("--key " + gnosKey)
                .addArgument("--outdir " + outputPrefix + "/" + gnosUploadDir)
                .addArgument("--metadata-urls " + gnosInputMetadataURLs)
                .addArgument("--upload-url " + gnosUploadFileURL)
                .addArgument("--bam-md5sum-file  /datastore/" + outputdir + "/" + pid + "/mpileup/" + file + ".md5 ");

        if (debugmode) {
            job.getCommand().addArgument("--test");
        }

        return (job);
    }

}
