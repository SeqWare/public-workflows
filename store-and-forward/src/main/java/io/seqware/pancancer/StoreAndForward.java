package io.seqware.pancancer;

import com.google.common.base.Joiner;
import com.google.common.collect.Lists;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.Map.Entry;
import net.sourceforge.seqware.pipeline.workflowV2.AbstractWorkflowDataModel;
import net.sourceforge.seqware.pipeline.workflowV2.model.Job;

/**
 * <p>
 * For more information on developing workflows, see the documentation at <a
 * href="http://seqware.github.io/docs/6-pipeline/java-workflows/">SeqWare Java Workflows</a>.
 * </p>
 *
 * Quick reference for the order of methods called: 1. setupDirectory 2. setupFiles 3. setupWorkflow 4. setupEnvironment 5. buildWorkflow
 *
 * See the SeqWare API for <a href=
 * "http://seqware.github.io/javadoc/stable/apidocs/net/sourceforge/seqware/pipeline/workflowV2/AbstractWorkflowDataModel.html#setupDirectory%28%29"
 * >AbstractWorkflowDataModel</a> for more information.
 */
public class StoreAndForward extends AbstractWorkflowDataModel {
  
    // job utilities
    private JobUtilities utils = new JobUtilities();

    // variables
    private static final String SHARED_WORKSPACE = "shared_workspace";
    private ArrayList<String> analysisIds = null;
    private ArrayList<String> bams = null;
    private ArrayList<String> downloadUrls = null;
    private String gnosServer = null;
    private String pemFile = null;
    private String studyRefnameOverride = null;
    private String analysisCenterOverride = null;
    private String formattedDate;
    private String commonDataDir = "";
    // skip
    private Boolean skipdownload = false;
    private Boolean skipupload = false;
    // cleanup
    private Boolean cleanup = true;
    // GNOS timeout
    private int gnosTimeoutMin = 20;
    private int gnosRetries = 3;
    // S3 
    private String controlS3URL = null;
    private ArrayList<String> tumourBamS3Urls = null;
    private ArrayList<String> allBamS3Urls = null;
    private String s3Key = null;
    private String s3SecretKey = null;
    private String uploadLocalPath = null;
    private String uploadS3BucketPath = null;
    // workflows to run
    // docker names
    private String gnosDownloadName = "seqware/pancancer_upload_download";
    
    @Override
    public void setupWorkflow() {
        try {
          
            // Idenfify Content
            String analysisId = getProperty("analysisIds");
            this.analysisIds = Lists.newArrayList(getProperty("analysisIds").split(","));
            this.bams = Lists.newArrayList(getProperty("bams").split(","));
	    
	    // GNOS DOWNLOAD
            this.gnosServer = getProperty("gnosServer");
            this.pemFile = getProperty("pemFile");
            for (String id : Lists.newArrayList(getProperty("analysisIds").split(","))) {
		StringBuilder downloadMetadataURLBuilder = new StringBuilder();
            	downloadMetadataURLBuilder.append(downloadServer).append("/cghub/metadata/analysisFull/").append(id);
		this.downloadUrls.append(downloadMetadataURLBuilder)
            }
            
            // S3 URLs
            s3Key = getProperty("s3Key");
            s3SecretKey = getProperty("s3SecretKey");
            uploadS3BucketPath = getProperty("uploadS3BucketPath");
            
            // shared data directory
            commonDataDir = getProperty("common_data_dir");

            // record the date
            DateFormat dateFormat = new SimpleDateFormat("yyyyMMdd");
            Calendar cal = Calendar.getInstance();
            this.formattedDate = dateFormat.format(cal.getTime());
            
            // timeout
            gnosTimeoutMin = Integer.parseInt(getProperty("gnosTimeoutMin"));
            gnosRetries = Integer.parseInt(getProperty("gnosRetries"));
            gnosDownloadName = getProperty("gnosDockerName");
	    
	    // skipping
	    this.skipdownload = getProperty("skipdownload");
	    this.skipdownupload = getProperty("skipupload");
	    
	    // cleanup
	    this.cleanup = getProperty("cleanup");
    
        } catch (Exception e) {
            throw new RuntimeException("Could not read property from ini", e);
        }
    }
    
    /*
     MAIN WORKFLOW METHOD
    */

    @Override
    /**
     * The core of the overall workflow
     */
    public void buildWorkflow() {

        // create a shared directory in /datastore on the host in order to download reference data
        Job createSharedWorkSpaceJob = createDirectoriesJob();
                 
        // download data from GNOS
        Job getGNOSJob = createGNOSJob(createSharedWorkSpaceJob);
        
        // upload data to S3
	Job s3Upload = createS3Job(getGNOSJob)
	
        // now cleanup
        cleanupWorkflow(s3Upload);
        
    }
    
    
    /*
     JOB BUILDING METHODS
    */
    
    private void cleanupWorkflow(Job lastJob) {
        if (cleanup) {
          Job cleanup = this.getWorkflow().createBashJob("cleanup");
	  cleanup.getCommand().addArgument("cd " + SHARED_WORKSPACE + " \n");
          cleanup.getCommand().addArgument("rm -rf downloads\* \n");
          cleanup.addParent(lastJob);
        } 
    }
    
    private Job createDirectoriesJob() {
	Job createSharedWorkSpaceJob = this.getWorkflow().createBashJob("create_dirs");
	createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + " \n");
	createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/settings \n");
	createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/results \n");
	createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/working \n");
	createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/downloads \n");
	createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/inputs \n");
	createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/testdata \n");
	createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/uploads \n");
	createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/data \n"); //deprecated, using data dirs below
	return(createSharedWorkSpaceJob);
    }

    private Job createGNOSJob(Job getReferenceDataJob) {
      Job GNOSjob = this.getWorkflow().createBashJob("GNOS_download");
      if (skipdownload == true)
	  GNOSjob.getCommand().addArgument("exit 0 \n");
      GNOSjob.getCommand().addArgument("cd " + SHARED_WORKSPACE + "/downloads \n");
      int index = 0;
      GNOSjob.getCommand().addArgument("date +%s > ../download_timing.txt \n");
      for (String url : this.downloadUrls) {
	  GNOSjob.getCommand().addArgument("echo '" + url + "' > individual_download_timing.txt \n");
	  GNOSjob.getCommand().addArgument("date +%s > individual_download_timing.txt  \n");
	  GNOSjob.getCommand().addArgument("docker run "
				      // link in the input directory
				      + "-v `pwd`:/workflow_data "
				      // link in the pem key
				      + "-v "
				      + pemFile
				      + ":/root/gnos_icgc_keyfile.pem " + gnosDownloadName
				      // here is the Bash command to be run
				      + " /bin/bash -c 'cd /workflow_data/ && perl -I /opt/gt-download-upload-wrapper/gt-download-upload-wrapper-2.0.10/lib "
				      + "/opt/vcf-uploader/vcf-uploader-2.0.4/gnos_download_file.pl "
				      + "--url " + url + " . "
				      + " --retries " + gnosRetries + " --timeout-min " + gnosTimeoutMin + " "
				      + "  --pem /root/gnos_icgc_keyfile.pem"
	  index += 1;
	  GNOSjob.getCommand().addArgument("date +%s > individual_download_timing.txt  \n");
	  GNOSjob.getCommand().addArgument("curl " + url + " > " + analysisId.get(index) + "/" + analysisId.get(index));
      }
      GNOSjob.getCommand().addArgument("date +%s > ../download_timing.txt \n");
      GNOSjob.getCommand().addArgument("cd - \n");
      GNOSjob.addParent(getReferenceDataJob);
      return(GNOSjob);
    }
  
    private Job createS3Job(Job getReferenceDataJob) {
      Job S3job = this.getWorkflow().createBashJob("S3_upload"):
       if (skipupload == true)
	  S3job.getCommand().addArgument("exit 0 \n");
      S3job.getCommand().addArgument("cd " + SHARED_WORKSPACE + "/downloads \n");
      S3job.getCommand().addArgument("date +%s > ../upload_timing.txt \n");
      int index = 0;
      for (String url : this.downloadUrls) {
	  S3job.getCommand().addArgument("python pathtopythonscript " + analysisId.get(index) + " " + s3Key + " " + s3SecretKey);
      }
      S3job.getCommand().addArgument("date +%s > ../upload_timing.txt \n");
      S3job.getCommand().addArgument("cd - \n");
      S3job.addParent(getReferenceDataJob);
      return(S3job);
    }

}
