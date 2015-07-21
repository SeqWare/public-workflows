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
    private String JSONlocation = "/datastore/gitroot";
    private String JSONrepoName = "s3-transfer-operations";
    private String JSONfolderName = null;
    private String JSONfileName = null;
    private String JSONxmlHash = null;
    private String GITemail = "nbyrne.oicr@gmail.com";
    private String GITname = "ICGC AUTOMATION";
    private String GITPemFile = null;
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
            
            // Collab Token
            this.collabToken = getProperty("collabToken");
            this.collabCertPath = getProperty("collabCertPath");
            this.collabHost = getProperty("collabHost");
            
            // Elasticsearch Git Repo
            this.JSONrepo = getProperty("JSONrepo");
            this.JSONfolderName = getProperty("JSONfolderName");
            this.JSONfileName = getProperty("JSONfileName");
            this.JSONxmlHash = getProperty("JSONxmlHash");
            this.GITemail = getProperty("GITemail");
            this.GITname = getProperty("GITname");
            this.GITPemFile = getProperty("GITPemFile");

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
        Job installDependenciesJob = pullRepo(createSharedWorkSpaceJob);
        
        // Move the JSON file to download
        Job move2download = gitMove(installDependenciesJob, "queued-jobs", "downloading-jobs");
        
        // download data from GNOS
        Job getGNOSJob = createGNOSJob(move2download);
        
        // Move the JSON file to verify
        Job move2verify = gitMove(getGNOSJob, "downloading-jobs", "verification-jobs");   
        
        // download verification
        Job verifyDownload = createVerifyJob(move2verify);
        
        // Move the JSON file to upload
        Job move2upload = gitMove(verifyDownload, "verification-jobs", "uploading-jobs");
        
        // upload data to S3
        Job s3Upload = S3toolJob(move2upload);
	
        // Move the JSON file to finished
        Job move2finished = gitMove(s3Upload, "uploading-jobs", "completed-jobs");
        
        // now cleanup
        cleanupWorkflow(move2finished);
        
    }
    
    /*
     JOB BUILDING METHODS
    */
    
    private Job gitMove(Job lastJob, String src, String dst) {
    	Job manageGit = this.getWorkflow().createBashJob("git_manage_" + src + "_" + dst);
    	String path = this.JSONlocation + "/" +  this.JSONrepoName + "/" + this.JSONfolderName;
    	String gitroot = this.JSONlocation + "/" +  this.JSONrepoName;
    	manageGit.getCommand().addArgument("git config --global user.name " + this.GITname + " \n");
    	manageGit.getCommand().addArgument("git config --global user.email " + this.GITemail + " \n");
    	manageGit.getCommand().addArgument("if [[ ! -d " + path + " ]]; then mkdir -p " + path + "; fi \n");
    	manageGit.getCommand().addArgument("cd " + path + " \n");
    	manageGit.getCommand().addArgument("# This is not idempotent: git pull \n");
    	manageGit.getCommand().addArgument("git fetch origin \n");
    	manageGit.getCommand().addArgument("git reset --hard origin/master \n");
    	manageGit.getCommand().addArgument("if [[ ! -d " + dst + " ]]; then mkdir " + dst + "; git add " + dst + "; fi \n");
    	manageGit.getCommand().addArgument("if [[ -d " + src + " ]]; then git mv " + path + "/" + src + "/" + this.JSONfileName + " " + path + "/" + dst + "; fi \n");
    	manageGit.getCommand().addArgument("git stage . \n");
    	manageGit.getCommand().addArgument("git commit -m '" + this.gnosServer + "' \n");
    	manageGit.getCommand().addArgument("git push \n");
    	manageGit.addParent(lastJob);
    	return(manageGit);
    }
    
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

    private Job pullRepo(Job getReferenceDataJob) {
    	Job installerJob = this.getWorkflow().createBashJob("install_dependencies");
    	installerJob.getCommand().addArgument("if [[ ! -d ~/.ssh/ ]]; then  mkdir ~/.ssh; fi \n");
    	installerJob.getCommand().addArgument("cp " + this.GITPemFile + " ~/.ssh/id_rsa \n");
    	installerJob.getCommand().addArgument("chmod 600 ~/.ssh/id_rsa \n");
    	installerJob.getCommand().addArgument("echo 'StrictHostKeyChecking no' > ~/.ssh/config \n");
    	installerJob.getCommand().addArgument("if [[ -d " + this.JSONlocation + " ]]; then  exit 0; fi \n");
    	installerJob.getCommand().addArgument("mkdir -p " + this.JSONlocation + " \n");
    	installerJob.getCommand().addArgument("cd " + this.JSONlocation + " \n");
    	installerJob.getCommand().addArgument("git config --global user.name " + this.GITname + " \n");
    	installerJob.getCommand().addArgument("git config --global user.email " + this.GITemail + " \n");
    	installerJob.getCommand().addArgument("git clone " + this.JSONrepo + " \n");
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
    			  + "-v `pwd`:/collab/upload "
    			  + "-v " + this.collabCertPath + ":/collab/storage/conf/client.jks "
    			  + "-e ACCESSTOKEN=" + this.collabToken + " "
    			  + "--net=\"host\" "
    			  + "-e CLIENT_STRICT_SSL=\"True\" "
    			  + "-e CLIENT_UPLOAD_SERVICEHOSTNAME=" + this.collabHost + " "
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
    	int index = 0;
    	for (String url : this.downloadMetadataUrls) {
    		verifyJob.getCommand().addArgument("python " + this.getWorkflowBaseDir() + "/scripts/download_check.py " + url + " " + this.JSONxmlHash + " \n");
    		verifyJob.getCommand().addArgument("mv patched.xml " + this.analysisIds.get(index) + ".xml \n");
    		verifyJob.getCommand().addArgument("mv "
  				  + this.analysisIds.get(index) + ".xml "
  				  + this.analysisIds.get(index) + " \n");
    		index += 1;
    	}
    	verifyJob.addParent(getReferenceDataJob);
    	return(verifyJob);
    }

}
