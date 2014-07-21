package io.seqware.pancancer;

/**
 * Mine
 */
import net.sourceforge.seqware.pipeline.workflowV2.AbstractWorkflowDataModel;
import java.util.ArrayList;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;
import net.sourceforge.seqware.pipeline.workflowV2.model.Job;
import net.sourceforge.seqware.pipeline.workflowV2.model.SqwFile;

public class DKFZSNVCallingWorkflow extends AbstractWorkflowDataModel {

    // GENERAL
    // comma-seperated for multiple bam inputs
    ArrayList<String> inputMetadataURLs = new ArrayList<String>();
    // used to download with gtdownload

    String gnosInputMetadataURLs = null;
    
    String gnosUploadFileURL = null;
    String gnosUploadDir = null;
    String gnosDownloadDir=null;
    
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
    boolean doAceSeq = false;
    

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
            
            gnosDownloadDir =getProperty("gnos_download_dir");
            
          
            gnosInputMetadataURLs = getProperty("gnos_input_metadata_urls");
            for (String url : gnosInputMetadataURLs.split(",")) {
                inputMetadataURLs.add(url);
            }

            gnosUploadFileURL = getProperty("gnos_output_file_url");
            gnosKey = getProperty("gnos_key");

            pid = getProperty("pid");
            gnosUploadDir = getProperty("gnos_upload_dir");

            inputFileNormal = getProperty("input_file_control");
            inputFileTumor = getProperty("input_file_tumor");
            
            inputFileDependencies = getProperty("input_file_dependencies");
            
            if (getProperty("clean_up") != null) {
                if ("true".equals(getProperty("clean_up"))) {
                    doCleanup = true;
                }
            }
            if (getProperty("debug_mode") != null) {
                if ("true".equals(getProperty("debug_mode"))) {
                    debugmode = true;
                    outputdir = "testdata";
                }
            }
            if (getProperty("snv_calling") != null) {
                if ("true".equals(getProperty("snv_calling"))) {
                    doSNVCalling = true;
                }
            }
            if (getProperty("indel_calling") != null) {
                if ("true".equals(getProperty("indel_calling"))) {
                    doIndelCalling = true;
                }
            }
            if (getProperty("ace_seq") != null) {
                if ("true".equals(getProperty("ace_seq"))) {
                    doAceSeq = true;
                }
            }

            gtdownloadRetries = getProperty("gtdownloadRetries") == null ? "30"
                    : getProperty("gtdownloadRetries");
            gtdownloadMd5Time = getProperty("gtdownloadMd5time") == null ? "120"
                    : getProperty("gtdownloadMd5time");
            gtdownloadMem = getProperty("gtdownloadMemG") == null ? "8"
                    : getProperty("gtdownloadMemG");
            smallJobMemM = getProperty("smallJobMemM") == null ? "3000"
                    : getProperty("smallJobMemM");
            if (getProperty("use_gtdownload") != null) {
                if ("false".equals(getProperty("use_gtdownload"))) {
                    useGtDownload = false;
                }
            }
            if (getProperty("use_gtupload") != null) {
                if ("false".equals(getProperty("use_gtupload"))) {
                    useGtUpload = false;
                }
            }
            
        } catch (Exception e) {
            Logger.getLogger(DKFZSNVCallingWorkflow.class.getName()).log(
                    Level.SEVERE, null, e);
            throw new RuntimeException("Problem parsing variable values: "
                    + e.getMessage());
        }

        return this.getFiles();
    }

    @Override
    public void setupDirectory() {        

    }

    @Override
    public void buildWorkflow() {


        Job createDirs = this.getWorkflow().createBashJob("CreateDirs");
        createDirs
                .getCommand()
                .addArgument("cd /"+outputPrefix)
                .addArgument("&& mkdir -p "+outputdir+"/"+pid+"/alignment")
                .addArgument("&& mkdir -p "+gnosDownloadDir)
                .addArgument("&& mkdir -p "+gnosUploadDir);
                

        // the download jobs that either downloads or locates the file on the
        // filesystem

        // download bam file tumor
        Job GNOSDownloadTumor = this.getWorkflow().createBashJob(
                "GNOSDownload Tumor");
        addDownloadJobArgs(GNOSDownloadTumor, inputFileTumor, "BAM", "tumor");
        GNOSDownloadTumor.setMaxMemory(gtdownloadMem + "000");
        GNOSDownloadTumor.addParent(createDirs);

        // download bam file normal
        Job GNOSDownloadNormal = this.getWorkflow().createBashJob(
                "GNOSDownload Normal");
        addDownloadJobArgs(GNOSDownloadNormal, inputFileNormal, "BAM", "control");
        GNOSDownloadNormal.setMaxMemory(gtdownloadMem + "000");
        GNOSDownloadNormal.addParent(createDirs);

        Job GNOSDownloadDependencies = this.getWorkflow().createBashJob(
                "GNOSDownload Dependencies");
        addDownloadJobArgs(GNOSDownloadDependencies, inputFileDependencies, "TAR", "dependencies");
        GNOSDownloadDependencies.setMaxMemory(gtdownloadMem + "000");
        GNOSDownloadDependencies.addParent(createDirs);


        Job SNVCalling = this.getWorkflow().createBashJob("SNVCalling");
        if (doSNVCalling) {
            SNVCalling.addParent(GNOSDownloadNormal);
            SNVCalling.addParent(GNOSDownloadTumor);
            SNVCalling.addParent(GNOSDownloadDependencies);
            SNVCalling.getCommand()
                    .addArgument(
                            "cd " + this.getWorkflowBaseDir()
                                    + "/RoddyBundlePancancer");
           if (debugmode) {
                SNVCalling
                        .getCommand()
                        .addArgument(
                                "&& bash roddy.sh run otpProjects_pancancer.dbg@snvCalling ")
                        .addArgument(pid)
                        .addArgument(
                                "--useconfig=applicationPropertiesAllLocal.ini")
                        .addArgument("--waitforjobs")
                        .addArgument("--verbositylevel=5 ");
            } else {
                SNVCalling
                        .getCommand()
                        .addArgument(
                                "&& bash roddy.sh run otpProjects_pancancer@snvCalling ")
                        .addArgument(pid)
                        .addArgument(
                                "--useconfig=applicationPropertiesAllLocal.ini")
                        .addArgument("--waitforjobs");
            }
            
            
            Job GNOSUploadRawVCF = this.getWorkflow().createBashJob("GNOSUpload Raw VCF");
            addUploadJobArgs(GNOSUploadRawVCF, "snvs_" + pid + "_raw.vcf.gz");
            GNOSUploadRawVCF.setMaxMemory(gtdownloadMem + "000");
            GNOSUploadRawVCF.addParent(SNVCalling);

            Job GNOSUploadVCF = this.getWorkflow().createBashJob("GNOSUpload VCF");
            addUploadJobArgs(GNOSUploadVCF, "snvs_" + pid + ".vcf.gz");
            GNOSUploadVCF.setMaxMemory(gtdownloadMem + "000");
            GNOSUploadVCF.addParent(SNVCalling);
            
            
        }
        
        Job indelCalling = this.getWorkflow().createBashJob("IndelCalling");
        if (doIndelCalling) {
            indelCalling.addParent(GNOSDownloadNormal);
            indelCalling.addParent(GNOSDownloadTumor);
            indelCalling.addParent(GNOSDownloadDependencies);
            indelCalling.getCommand()
                    .addArgument(
                            "cd " + this.getWorkflowBaseDir()
                                    + "/RoddyBundlePancancer");
            if (debugmode) {
                indelCalling
                        .getCommand()
                        .addArgument(
                                "&& bash roddy.sh run otpProjects_pancancer.dbg@indelCalling ")
                        .addArgument(pid)
                        .addArgument(
                                "--useconfig=applicationPropertiesAllLocal.ini")
                        .addArgument("--waitforjobs")
                        .addArgument("--verbositylevel=5 ");
            } else {
                indelCalling
                        .getCommand()
                        .addArgument(
                                "&& bash roddy.sh run otpProjects_pancancer@indelCalling ")
                        .addArgument(pid)
                        .addArgument(
                                "--useconfig=applicationPropertiesAllLocal.ini")
                        .addArgument("--waitforjobs");
            }
        }
        
        Job aceSeq = this.getWorkflow().createBashJob("AceSeq");
        if (doAceSeq) {
            aceSeq.addParent(GNOSDownloadNormal);
            aceSeq.addParent(GNOSDownloadTumor);
            aceSeq.addParent(GNOSDownloadDependencies);
            aceSeq.getCommand()
                    .addArgument(
                            "cd " + this.getWorkflowBaseDir()
                                    + "/RoddyBundlePancancer");
            if (debugmode) {
                aceSeq
                        .getCommand()
                        .addArgument(
                                "&& bash roddy.sh run otpProjects_pancancer.dbg@aceSeq ")
                        .addArgument(pid)
                        .addArgument(
                                "--useconfig=applicationPropertiesAllLocal.ini")
                        .addArgument("--waitforjobs")
                        .addArgument("--verbositylevel=5 ");
            } else {
                aceSeq
                        .getCommand()
                        .addArgument(
                                "&& bash roddy.sh run otpProjects_pancancer@aceSeq ")
                        .addArgument(pid)
                        .addArgument(
                                "--useconfig=applicationPropertiesAllLocal.ini")
                        .addArgument("--waitforjobs");
            }
        }
        

        // // CLEANUP DOWNLOADED INPUT BAM FILES
        if (doCleanup) {
            Job cleanup = this.getWorkflow().createBashJob("clean up");
            cleanup.getCommand().addArgument(
                    "rm -fr /"+outputPrefix+"/" + outputdir +" ;");
            cleanup.getCommand().addArgument(
                    "rm -fr /"+outputPrefix+"/"+gnosDownloadDir+";");
            cleanup.getCommand().addArgument(
                    "rm -fr /"+outputPrefix+"/"+gnosUploadDir+" ;");

            cleanup.setMaxMemory(smallJobMemM);
            cleanup.addParent(SNVCalling);
            cleanup.addParent(indelCalling);
            cleanup.addParent(aceSeq);

        }
    }

    private Job addDownloadJobArgs(Job job, String fileURL,
            String filetype, String type) {


        String[] urlElements = fileURL.split("/");
        String dir = urlElements[urlElements.length - 1];

        job.getCommand()
                .addArgument(
                        "perl " + this.getWorkflowBaseDir()
                                + "/scripts/launch_and_monitor_gnos.pl")
                .addArgument("--command 'gtdownload -c " + gnosKey + " -d "
                                + fileURL + " -p /datastore/gnos_download '")
                .addArgument("--file-grep " + dir)
                .addArgument("--search-path .")
                .addArgument("--retries " + gtdownloadRetries)
                .addArgument("--md5-retries " + gtdownloadMd5Time + ";");

        if (filetype.equalsIgnoreCase("BAM")) {
            String bamTumorSrc = "/"+outputPrefix+"/"+gnosDownloadDir+"/" + dir + "/*.bam";
            String bamTumorDst = "/"+outputPrefix+"/"+ outputdir + "/" + pid
                    + "/alignment/" + type + "_" + pid + "_merged.mdup.bam";
            job.getCommand().addArgument(
                    String.format("ln -sn %s  %s ;",
                            bamTumorSrc, bamTumorDst));
            String baiTumorSrc = "/"+outputPrefix+"/"+gnosDownloadDir+"/" + dir
                    + "/*.bam.bai";
            String baiTumorDst = "/"+outputPrefix+"/"+ outputdir + "/" + pid
                    + "/alignment/" + type + "_" + pid + "_merged.mdup.bam.bai";
            job.getCommand().addArgument(
                    String.format("ln -sf %s  %s ;",
                            baiTumorSrc, baiTumorDst));
        }
        if (filetype.equalsIgnoreCase("TAR")) {
            job.getCommand()
                    .addArgument(
                            "cd /" + outputPrefix
                                    + " && if [ ! -d \"bundledFiles\" ]; ")
                    .addArgument(
                            "then  ln -sf  /" + outputPrefix + "/"
                                    + gnosDownloadDir + "/" + dir
                                    + "/*tar.gz  /" + outputPrefix
                                    + "/workflow-dependencies.tar.gz ;")
                    .addArgument(
                            " tar -xvf /" + outputPrefix
                                    + "/workflow-dependencies.tar.gz  && rm  /"
                                    + outputPrefix
                                    + "/workflow-dependencies.tar.gz ; fi");
        }
        return (job);
    }

    private Job addUploadJobArgs(Job job, String file) {
        
        job.getCommand()
                .addArgument(
                        " cd /"+outputPrefix+"/" + outputdir + "/" + pid
                                + "/mpileup/ && md5sum " + file
                                + " | awk '{printf $1}'")
                .addArgument(" > " + file + ".md5 ;");

        job.getCommand()
                .addArgument(
                        "perl " + this.getWorkflowBaseDir()
                                + "/scripts/gnos_upload_data.pl")
                .addArgument(
                        "--bam /"+outputPrefix+"/" + outputdir + "/" + pid
                                + "/mpileup/" + file)
                .addArgument("--key " + gnosKey)
                .addArgument("--outdir " + outputPrefix+"/"+gnosUploadDir)
                .addArgument("--metadata-urls " + gnosInputMetadataURLs)
                .addArgument("--upload-url " + gnosUploadFileURL)
                .addArgument(
                        "--bam-md5sum-file  /datastore/" + outputdir + "/"
                                + pid + "/mpileup/" + file + ".md5 ");

        if (debugmode) {
            job.getCommand().addArgument("--test");
        }

        return (job);
    }

}
