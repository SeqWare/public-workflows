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
    String inputBamPaths = null;
    ArrayList<String> bamPaths = new ArrayList<String>();
    ArrayList<String> inputURLs = new ArrayList<String>();
    ArrayList<String> inputMetadataURLs = new ArrayList<String>();
    // used to download with gtdownload
    String gnosInputFileURLs = null;
    String gnosInputMetadataURLs = null;
    String gnosUploadFileURL = null;
    String gnosKey = null;
    boolean useGtDownload = true;
    boolean useGtUpload = true;
    // number of splits for bam files, default 1=no split
    int bamSplits = 1;
    String reference_path = null;
    String dataDir = "data/";
    String outputDir = "results";
    String outputPrefix = "./";
    String resultsDir = outputPrefix + outputDir;
    String outputFileName = "merged_output.bam";
    // GTDownload
    // each retry is 1 minute
    String gtdownloadRetries = "30";
    String gtdownloadMd5Time = "120";
    String gtdownloadMem = "8";
    String smallJobMemM = "3000";
    String inputFileTumor = null;
    String inputFileNormal = null;
    @Override
    public Map<String, SqwFile> setupFiles() {

        /*
         * This workflow isn't using file provisioning since we're using
         * GeneTorrent. So this method is just being used to setup various
         * variables.
         */
        try {

            inputBamPaths = getProperty("input_bam_paths");
            for (String path : inputBamPaths.split(",")) {
                bamPaths.add(path);
            }
            gnosInputFileURLs = getProperty("gnos_input_file_urls");
            for (String url : gnosInputFileURLs.split(",")) {
                inputURLs.add(url);
            }
            gnosInputMetadataURLs = getProperty("gnos_input_metadata_urls");
            for (String url : gnosInputMetadataURLs.split(",")) {
                inputMetadataURLs.add(url);
            }
            outputDir = this.getMetadata_output_dir();
            outputPrefix = this.getMetadata_output_file_prefix();
            resultsDir = outputPrefix + outputDir;
            gnosUploadFileURL = getProperty("gnos_output_file_url");
            gnosKey = getProperty("gnos_key");
            gtdownloadRetries = getProperty("gtdownloadRetries") == null ? "30"
                    : getProperty("gtdownloadRetries");
            gtdownloadMd5Time = getProperty("gtdownloadMd5time") == null ? "120"
                    : getProperty("gtdownloadMd5time");
            gtdownloadMem = getProperty("gtdownloadMemG") == null ? "8"
                    : getProperty("gtdownloadMemG");
            smallJobMemM = getProperty("smallJobMemM") == null ? "3000"
                    : getProperty("smallJobMemM");
    //        inputFileNormal = getProberty("inputFileNormal");
    //        inputFileTumor = getProberty("inputFileTumor");
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
        // creates the final output
        this.addDirectory(dataDir);
        this.addDirectory(resultsDir);
    }

    @Override
    public void buildWorkflow() {


        // the download job that either downloads or locates the file on the
        // filesystem

        //download bam file tumor 
        Job GNOSDownloadTumor = this.getWorkflow().createBashJob("GNOSDownloadTumor");
        addDownloadJobArgs(GNOSDownloadTumor, bamPaths.get(0), inputURLs.get(0));
        GNOSDownloadTumor.setMaxMemory(gtdownloadMem + "000");

        //TODO: create index file with Samtools for bam file tumor
        
        //download bam file normal 
        Job GNOSDownloadNormal = this.getWorkflow().createBashJob("GNOSDownloadNormal");
        addDownloadJobArgs(GNOSDownloadNormal, bamPaths.get(1), inputURLs.get(1));
        GNOSDownloadNormal.setMaxMemory(gtdownloadMem + "000");
        GNOSDownloadNormal.addParent(GNOSDownloadTumor);
        
        //TODO: create index file with Samtools for bam file normal

//        Job SNVCalling = this.getWorkflow().createBashJob("SNVCalling");
// //       SNVCalling.addParent(GNOSDownloadNormal);
//        SNVCalling.getCommand().addArgument("cd "+this.getWorkflowBaseDir()+"/RoddyBundlePancancer && bash roddy.sh run otpProjects_pancancer.dbg@snvCalling A100 " +
//        		"--useconfig=applicationPropertiesAllLocal.ini --waitforjobs --verbositylevel=5 ");

        // TODO: look at Kerien's code for generating GNOS metadata

        // The directory:
        // analysis/DKFZ/SNV/panCancer/{GNOSDonorID}/mpileup[_indel]/[snvs|indels]_{GNOSDonorID}.vcf.gz
        Job GNOSUpload = this.getWorkflow().createBashJob("GNOSUpload");
        // GNOSUpload.getCommand().addArgument(this.getWorkflowBaseDir()+"/bin/upload_gnos.pl "+getProperty("GNOSDonorID")+" analysis/DKFZ/SNV/panCancer/{GNOSDonorID}/mpileup[_indel]/[snvs|indels]_{GNOSDonorID}.vcf.gz");
    //    GNOSUpload.addParent(SNVCalling);

        // // CLEANUP DOWNLOADED INPUT UNALIGNED BAM FILES
        // if (useGtDownload) {
        // Job cleanup1 = this.getWorkflow().createBashJob("cleanup_" + i);
        // cleanup1.getCommand().addArgument("rm -f " + file);
        // cleanup1.setMaxMemory(smallJobMemM);
        // cleanup1.addParent(GNOSUpload);
        // }

    }

    private Job addDownloadJobArgs(Job job, String file, String fileURL) {

        // a little unsafe
        String[] pathElements = file.split("/");
        String analysisId = pathElements[0];
        job.getCommand()
                .addArgument(
                        "perl " + this.getWorkflowBaseDir()
                                + "/scripts/launch_and_monitor_gnos.pl")
                .addArgument(
                        "--command 'gtdownload -c " + gnosKey + " -vv -d "
                                + fileURL + "'")
                .addArgument("--file-grep " + analysisId)
                .addArgument("--search-path .")
                .addArgument("--retries " + gtdownloadRetries)
                .addArgument("--md5-retries " + gtdownloadMd5Time);
        return (job);
    }


}

