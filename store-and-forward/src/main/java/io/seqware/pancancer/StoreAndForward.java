package io.seqware.pancancer;

import com.google.common.base.Joiner;
import com.google.common.collect.Lists;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.Map.Entry;
import java.lang.Long;
import net.sourceforge.seqware.pipeline.workflowV2.AbstractWorkflowDataModel;
import net.sourceforge.seqware.pipeline.workflowV2.model.Job;

/**
 * <p>
 * For more information on developing workflows, see the documentation at <a
 * href="http://seqware.github.io/docs/6-pipeline/java-workflows/">SeqWare Java Workflows</a>.
 * </p>
 *
 * Quick reference for the order of steps: 1. setupDirectory 2. GNOS Download 3. Verify Files 4. S3Upload 5. Notify ElasticSearch 6. Cleanup
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
    private ArrayList<String> downloadMetadataUrls = null;
    private String gnosServer = null;
    private String pemFile = null;
    private String formattedDate;
    // skip
    private Boolean skipdownload = false;
    private Boolean skipupload = false;
    // cleanup
    private Boolean cleanup = true;
    // GNOS timeout
    private int gnosTimeoutMin = 20;
    private int gnosRetries = 3;
    // S3 
    private String s3Key = null;
    private String s3SecretKey = null;
    private String uploadS3Bucket = null;
    private String uploadTimeout = null;
    // JSON repo
    private String JSONrepo = null;
    // Colabtool
    private String collabToken = null;
    private String collabCertPath = null;
    private String collabHost = null;
    // workflows to run
    // docker names
    private String gnosDownloadName = "seqware/pancancer_upload_download";
    
    @Override
    public void setupWorkflow() {
        try {
          
            // Idenfify Content
            this.analysisIds = Lists.newArrayList(getProperty("analysisIds").split(","));
	    
            // GNOS DOWNLOAD:
            
            // This may end up being a list of servers, just take the first element for now
            // We can add more logic later
            this.gnosServer = getProperty("gnosServers").split(",")[0];
            
            this.pemFile = getProperty("pemFile");
            this.downloadMetadataUrls = Lists.newArrayList();
            this.downloadUrls = Lists.newArrayList();
            for (String id : Lists.newArrayList(getProperty("analysisIds").split(","))) {
            	StringBuilder downloadMetadataURLBuilder = new StringBuilder();
            	StringBuilder downloadDataURLBuilder = new StringBuilder();
            	downloadMetadataURLBuilder.append(gnosServer).append("/cghub/metadata/analysisFull/").append(id);
            	downloadDataURLBuilder.append(gnosServer).append("/cghub/data/analysis/download/").append(id);
            	this.downloadUrls.add(downloadDataURLBuilder.toString());
            	this.downloadMetadataUrls.add(downloadMetadataURLBuilder.toString());
            }
            
            // S3 UPLOAD - Legacy for 1.0.1
            this.s3Key = getProperty("S3UploadKey");
            this.s3SecretKey = getProperty("S3UploadSecretKey");
            this.uploadS3Bucket = getProperty("S3UploadBucket");
            this.uploadTimeout = getProperty("S3UploadTimeout");
            
            // Collab Token
            this.collabToken = getProperty("collabToken");
            this.collabCertPath = getProperty("collabCertPath");
            this.collabHost = getProperty("collabHost");

            // record the date
            DateFormat dateFormat = new SimpleDateFormat("yyyyMMdd");
            Calendar cal = Calendar.getInstance();
            this.formattedDate = dateFormat.format(cal.getTime());
            
            // GNOS timeouts
            if(hasPropertyAndNotNull("gnosTimeoutMin"))
            		this.gnosTimeoutMin = Integer.parseInt(getProperty("gnosTimeoutMin"));
            if(hasPropertyAndNotNull("gnosRetries"))
            		this.gnosRetries = Integer.parseInt(getProperty("gnosRetries"));
            if(hasPropertyAndNotNull("gnosDockerName"))
            		this.gnosDownloadName = getProperty("gnosDockerName");
	    
		    // skipping
	        if(hasPropertyAndNotNull("skipdownload")) {
	        	this.skipdownload = Boolean.valueOf(getProperty("skipdownload").toLowerCase());
	        }
	        if(hasPropertyAndNotNull("skipupload")) {
	        	this.skipupload = Boolean.valueOf(getProperty("skipupload").toLowerCase());
	        }
	        
		    // cleanup
	        if(hasPropertyAndNotNull("cleanup")) {
	        	this.cleanup = Boolean.valueOf(getProperty("cleanup"));
	        }
	    
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
        
        // Install Dependencies for Ubuntu
        Job installDependenciesJob = installDependencies(createSharedWorkSpaceJob);
                 
        // download data from GNOS
        Job getGNOSJob = createGNOSJob(installDependenciesJob);
        
        // download verification
        Job verifyDownload = createVerifyJob(getGNOSJob);
        
        // upload data to S3
        Job s3Upload = S3toolJob(verifyDownload);
	
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
          cleanup.getCommand().addArgument("rm -rf downloads\\* \n");
          cleanup.addParent(lastJob);
        } 
    }
    
    private Job createDirectoriesJob() {
		Job createSharedWorkSpaceJob = this.getWorkflow().createBashJob("create_dirs");
		createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + " \n");
		createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/downloads \n");
		return(createSharedWorkSpaceJob);
    }

    private Job installDependencies(Job getReferenceDataJob) {
    	Job installerJob = this.getWorkflow().createBashJob("install_dependencies");
    	installerJob.getCommand().addArgument("sudo apt-get install git || echo \n");
    	installerJob.getCommand().addArgument("[[ -d /home/ubuntu/gitroot ]] && mkdir -m 0777 -p /home/ubuntu/gitroot && cd /home/ubuntu/gitroot && git clone " + this.JSONrepo + " \n");
    	installerJob.addParent(getReferenceDataJob);
    	return(installerJob);
    }
    
    private Job createGNOSJob(Job getReferenceDataJob) {
	  Job GNOSjob = this.getWorkflow().createBashJob("GNOS_download");
	  if (this.skipdownload == true) {
		  GNOSjob.getCommand().addArgument("exit 0 \n");
	  }
	  GNOSjob.getCommand().addArgument("cd " + SHARED_WORKSPACE + "/downloads \n");
	  int index = 0;
	  GNOSjob.getCommand().addArgument("date +%s > ../download_timing.txt \n");
	  for (String url : this.downloadUrls) {
		  GNOSjob.getCommand().addArgument("echo '" + url + "' > individual_download_timing.txt \n");
		  GNOSjob.getCommand().addArgument("date +%s > individual_download_timing.txt \n");
		  GNOSjob.getCommand().addArgument("curl " 
		  		  + this.downloadMetadataUrls.get(index) 
		  		  + " > " + this.analysisIds.get(index) + ".xml \n");
		  GNOSjob.getCommand().addArgument("sudo docker run "
					      // link in the input directory
					      + "-v `pwd`:/workflow_data "
					      // link in the pem key
					      + "-v "
					      + this.pemFile
					      + ":/root/gnos_icgc_keyfile.pem " + this.gnosDownloadName
					      // here is the Bash command to be run
					      + " /bin/bash -c \"cd /workflow_data/ && perl -I /opt/gt-download-upload-wrapper/gt-download-upload-wrapper-2.0.10/lib "
					      + "/opt/vcf-uploader/vcf-uploader-2.0.4/gnos_download_file.pl "
					      + "--url " + url + " . "
					      + " --retries " + this.gnosRetries + " --timeout-min " + this.gnosTimeoutMin + " "
					      + " --file /root/gnos_icgc_keyfile.pem "
					      + " --pem /root/gnos_icgc_keyfile.pem\" \n");
		  GNOSjob.getCommand().addArgument("sudo chown -R seqware:seqware " + this.analysisIds.get(index) + " \n");
		  GNOSjob.getCommand().addArgument("mv "
				  + this.analysisIds.get(index) + ".xml "
				  + this.analysisIds.get(index) + " \n");
		  GNOSjob.getCommand().addArgument("date +%s > individual_download_timing.txt \n");
		  index += 1;
	  }
	  GNOSjob.getCommand().addArgument("date +%s > ../download_timing.txt \n");
	  GNOSjob.getCommand().addArgument("cd - \n");
	  GNOSjob.addParent(getReferenceDataJob);
	  return(GNOSjob);
    }
    
    private Job S3toolJob( Job getReferenceDataJob) {
      Job S3job = this.getWorkflow().createBashJob("S3_upload");
      if (skipupload == true) {
    	  S3job.getCommand().addArgument("# Skip upload was turned on in your ini file \n");
    	  S3job.getCommand().addArgument("exit 0 \n");
      }
	  S3job.getCommand().addArgument("cd " + SHARED_WORKSPACE + "/downloads \n");
      S3job.getCommand().addArgument("date +%s > ../upload_timing.txt \n");
      int index = 0;
      for (String url : this.downloadUrls) {
    	  // Execute the collab tool, mounting the downloads folder into /collab/upload
    	  String folder = analysisIds.get(index);
    	  S3job.getCommand().addArgument("docker run "
    			  + "-v " + SHARED_WORKSPACE + "/downloads:/collab/upload "
    			  + "-v " + this.collabCertPath + ":/collab/storage/conf/client.jks "
    			  + "-e ACCESS_TOKEN=" + this.collabToken + " "
    			  + "-e CLIENT_STRICT_SSL=\"True\" "
    			  + "-e CLIENT_UPLOAD_SERVICE_HOSTNAME=" + this.collabHost + " "
    			  + "icgc/cli bash -c \"/collab/upload.sh /collab/upload/" + this.analysisIds.get(index)+"\" \n"
    			  );
    	  index += 1;
      }
      S3job.addParent(getReferenceDataJob);
      return(S3job);
    }
  
    
    private Job createVerifyJob(Job getReferenceDataJob) {
    	Job verifyJob = this.getWorkflow().createBashJob("Download_Verify");
    	verifyJob.getCommand().addArgument("cd " + SHARED_WORKSPACE + "/downloads \n");
    	for (String url : this.downloadMetadataUrls) {
    		verifyJob.getCommand().addArgument("python " + this.getWorkflowBaseDir() + "/scripts/download_check.py " + url + " \n");
    	}
    	verifyJob.addParent(getReferenceDataJob);
    	return(verifyJob);
    }

}
