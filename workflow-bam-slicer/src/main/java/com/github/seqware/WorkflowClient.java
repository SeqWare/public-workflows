package com.github.seqware;

/**
 * Mine
 */
import ca.on.oicr.pde.utilities.workflows.OicrWorkflow;
import java.util.ArrayList;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;
import net.sourceforge.seqware.pipeline.workflowV2.model.Job;
import net.sourceforge.seqware.pipeline.workflowV2.model.SqwFile;

public class WorkflowClient extends OicrWorkflow {

  // GENERAL
  // comma-separated for multiple bam inputs
  String inputBamPaths = null;
  ArrayList<String> bamPaths = new ArrayList<String>();
  
  // used to download with gtdownload
  String gnosInputFileURLs = null;
  ArrayList<String> inputURLs = new ArrayList<String>();

  String gnosInputMetadataURLs = null;
  ArrayList<String> inputMetadataURLs = new ArrayList<String>();

  String gnosUploadFileURL = null;
  String gnosKey = null;
  String jobDescription = "";
  String unmappedReadJobDescription = "";
  
  boolean useGtDownload = true;
  boolean useGtUpload = true;
  boolean isTesting = true;
  boolean extract_and_upload_unmapped_reads = true;

  String outputDir = "results";
  String outputPrefix = "./";
  String resultsDir = outputPrefix + outputDir;
  
  String outputFileName = "merged_output.bam";
  String outputUnmappedFileName = "merged_output.unmapped.bam";
  
  String mergeJobMemG = "4";

  String skipUpload = null;

  String pcapPath = "/bin/PCAP-core-1.0.4";
  
  // GTDownload
  // each retry is 1 minute
  String gtdownloadRetries = "30";
  String gtdownloadMd5Time = "120";
  String gtdownloadMemG = "8";
  String gtuploadMemG = "8";
  String smallJobMemM = "2000";

  @Override
  public Map<String, SqwFile> setupFiles() {

     /*
     This workflow isn't using file provisioning since 
     we're using GeneTorrent. So this method is just being
     used to setup various variables.
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
      
      outputDir = getProperty("output_dir"); // this.getMetadata_output_dir();  // not sure what this method does
      outputPrefix = getProperty("output_prefix"); // this.getMetadata_output_file_prefix();  // not sure what this method does
      resultsDir = outputPrefix + outputDir;
      
      gnosUploadFileURL = getProperty("gnos_output_file_url");
      gnosKey = getProperty("gnos_key");
      jobDescription = getProperty("job_description_encode");
      jobDescription = jobDescription.replace(" ", "\\ ").replace("(", "\\(").replace(")", "\\)");
      unmappedReadJobDescription = getProperty("job_description_unmapped");
      unmappedReadJobDescription = unmappedReadJobDescription.replace(" ", "\\ ").replace("(", "\\(").replace(")", "\\)");

      skipUpload = getProperty("skip_upload") == null ? "true" : getProperty("skip_upload");
      gtdownloadRetries = getProperty("gtdownloadRetries") == null ? "30" : getProperty("gtdownloadRetries");
      gtdownloadMd5Time = getProperty("gtdownloadMd5time") == null ? "120" : getProperty("gtdownloadMd5time");
      
      gtdownloadMemG = getProperty("gtdownloadMemG") == null ? "8" : getProperty("gtdownloadMemG");
      gtuploadMemG = getProperty("gtuploadMemG") == null ? "8" : getProperty("gtuploadMemG");
      smallJobMemM = getProperty("smallJobMemM") == null ? "2000" : getProperty("smallJobMemM");
      mergeJobMemG = getProperty("mergeJobMemG") == null ? "4" : getProperty("mergeJobMemG");
      
      if (getProperty("use_gtdownload") != null && "false".equals(getProperty("use_gtdownload"))) { useGtDownload = false; }
      if (getProperty("use_gtupload") != null && "false".equals(getProperty("use_gtupload"))) { useGtUpload = false; }
      if (getProperty("isTesting") != null && "false".equals(getProperty("isTesting"))) { isTesting = false; }
      if (getProperty("extract_and_upload_unmapped_reads") != null && "false".equals(getProperty("extract_and_upload_unmapped_reads"))) { extract_and_upload_unmapped_reads = false; }

    } catch (Exception e) {
      Logger.getLogger(WorkflowClient.class.getName()).log(Level.SEVERE, null, e);
      throw new RuntimeException("Problem parsing variable values: "+e.getMessage());
    }

    return this.getFiles();
  }

  @Override
  public void setupDirectory() {
    // creates the final output dir
    this.addDirectory(resultsDir);
  }

  @Override
  public void buildWorkflow() {

    int numBamFiles = bamPaths.size();
    ArrayList<Job> firstPartJobs = new ArrayList<Job>();
    ArrayList<Job> firstPartUnmappedReadJobs = new ArrayList<Job>();

    int numInputURLs = this.inputURLs.size();
    for (int i = 0; i < numInputURLs; i++) {
      
      // the file downloaded will be in this path
      String file = bamPaths.get(i);
      // the URL to download this from
      String fileURL = inputURLs.get(i);
        
      // the download job that either downloads or locates the file on the file system
      Job downloadJob = null;
      if (useGtDownload) {
        downloadJob = this.getWorkflow().createBashJob("gtdownload" + i);
        addDownloadJobArgs(downloadJob, file, fileURL);
        downloadJob.setMaxMemory(gtdownloadMemG + "000");
      }
      
      // dump out the original header for later use
      Job headerJob = null;
      headerJob = this.getWorkflow().createBashJob("headerJob" + i);
      //headerJob.getCommand().addArgument(this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view -H " + file + " | sed 's/\\t/\\\\t/g' > bam_header." + i + ".txt");
      headerJob.getCommand().addArgument("samtools view -H " + file + " | sed 's/\\t/\\\\t/g' > bam_header." + i + ".txt");
      headerJob.setMaxMemory("8000");

      if (useGtDownload) {
    	  headerJob.addParent(downloadJob);
      }
      
      // build BAM index file if it does not exist
      Job buildBamIndex = this.getWorkflow().createBashJob("buildBamIndex" + i);
      buildBamIndex.getCommand().addArgument(
    		  "test -s " + file + ".bai || "
    		  + "cat " + file + " | "
    		  + this.getWorkflowBaseDir() + pcapPath + "/bin/bamindex "
    		  + "> " + file + ".bai");

      buildBamIndex.setMaxMemory("4000");
      buildBamIndex.addParent(headerJob);      
      
      // slice out the reads within the specified regions in a BED file
      Job firstSliceJob = this.getWorkflow().createBashJob("firstSlice" + i);
      firstSliceJob.getCommand().addArgument(
    		  this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view -h -L "  // this will include single-end-mapped reads and their unmapped mates (which share the same rname and pos)
    		  + this.getWorkflowBaseDir() + "/scripts/encodeRegions.bed "
    		  + file
    		  + " | perl " + this.getWorkflowBaseDir() + "/scripts/remove_both_ends_unmapped_reads.pl "  // this is necessary because samtools -L outputs both-ends-unmapped reads
    		  + " | "
    		  + this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view -S -b - "
    		  + " > firstSlice." + i + ".bam");
      
      firstSliceJob.setMaxMemory("4000");
      firstSliceJob.addParent(buildBamIndex);
      
      // extract unmapped reads (both ends or either end unmapped)
      Job unmappedReadsJob1;
      Job unmappedReadsJob2;
      Job unmappedReadsJob3;
      if (extract_and_upload_unmapped_reads) {
    	  unmappedReadsJob1 = this.getWorkflow().createBashJob("unmappedReads1." + i);
    	  unmappedReadsJob1.getCommand().addArgument(
        		  this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view -h -f 4 " // reads unmapped
        		  + file
        		  + " | perl " + this.getWorkflowBaseDir() + "/scripts/remove_both_ends_unmapped_reads.pl "  // this is necessary because samtools -f 4 outputs both-ends-unmapped reads
        		  + " | "
        		  + this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view -S -b - "
        		  + " > unmappedReads1." + i + ".bam");
    	  unmappedReadsJob1.setMaxMemory("4000");
    	  unmappedReadsJob1.addParent(buildBamIndex);
    	  
    	  unmappedReadsJob2 = this.getWorkflow().createBashJob("unmappedReads2." + i);
    	  unmappedReadsJob2.getCommand().addArgument(
        		  this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view -h -f 8 " // reads' mate unmapped
        		  + file
        		  + " | perl " + this.getWorkflowBaseDir() + "/scripts/remove_both_ends_unmapped_reads.pl "  // this is necessary because samtools -f 8 outputs both-ends-unmapped reads
        		  + " | "
        		  + this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view -S -b - "
        		  + " > unmappedReads2." + i + ".bam");
    	  unmappedReadsJob2.setMaxMemory("4000");
    	  unmappedReadsJob2.addParent(buildBamIndex);
    	  
    	  unmappedReadsJob3 = this.getWorkflow().createBashJob("unmappedReads3." + i);
    	  unmappedReadsJob3.getCommand().addArgument(
        		  this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view -h -b -f 12 " // reads with both ends unmapped
        		  + file
        		  + " > unmappedReads3." + i + ".bam");
    	  unmappedReadsJob3.setMaxMemory("4000");
    	  unmappedReadsJob3.addParent(buildBamIndex);

    	  firstPartUnmappedReadJobs.add(unmappedReadsJob1);
    	  firstPartUnmappedReadJobs.add(unmappedReadsJob2);
    	  firstPartUnmappedReadJobs.add(unmappedReadsJob3);
    	  
      }

      
      // find out the orphaned reads in the sliced out BAM
      Job orphanedRead = this.getWorkflow().createBashJob("orphanedReads" + i);
      orphanedRead.getCommand().addArgument("LD_LIBRARY_PATH=" + this.getWorkflowBaseDir() + pcapPath + "/lib") 
          .addArgument(this.getWorkflowBaseDir() + pcapPath + "/bin/bamcollate2")
          .addArgument("collate=1")
          .addArgument("classes=O,O2")
          .addArgument("O=firstSliceOrphaned." + i + ".bam")
          .addArgument("filename=" + "firstSlice." + i + ".bam");
      
      orphanedRead.setMaxMemory("4000");
      orphanedRead.addParent(firstSliceJob);
      
      // generate BED file for second round slicing
      Job getMissingMateRegions = this.getWorkflow().createBashJob("getMissingMateRegions" + i);
      getMissingMateRegions.getCommand().addArgument(
    		  this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view "
    		  + "firstSliceOrphaned." + i + ".bam "
    		  + " | "
    	      + "perl " + this.getWorkflowBaseDir() + "/scripts/gen_missing_mates_bed.pl > missing_mates." + i + ".bed"
          );

      getMissingMateRegions.setMaxMemory(smallJobMemM);
      getMissingMateRegions.addParent(orphanedRead);

      Job secondSliceJob = this.getWorkflow().createBashJob("secondSlice" + i);
      secondSliceJob.getCommand().addArgument(
    		  this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view -F 12 -L "  // this will capture mapped ends which are out side of the target regions, but their mates were captured in the first slicing
    		  + "missing_mates." + i + ".bed "
    		  + file
    		  + " | "
    		  + "perl " + this.getWorkflowBaseDir() + "/scripts/extract_missing_mates.pl "
    		  + "bam_header." + i + ".txt "
    		  + "missing_mates." + i + ".bed "
    		  + " | "
    		  + this.getWorkflowBaseDir() + pcapPath + "/bin/samtools view -S -b - "
    		  + "> secondSlice." + i + ".bam");
      
      secondSliceJob.setMaxMemory("4000");
      secondSliceJob.addParent(getMissingMateRegions);
      
      firstPartJobs.add(secondSliceJob);
      
    }

    // MERGE 
    Job mergeJob = this.getWorkflow().createBashJob("mergeBAM");

    int numThreads = 1;
    if (getProperty("numOfThreads") != null && !getProperty("numOfThreads").isEmpty()) {
      numThreads = Integer.parseInt(getProperty("numOfThreads"));
    }
    mergeJob.getCommand().addArgument("LD_LIBRARY_PATH=" + this.getWorkflowBaseDir() + pcapPath + "/lib") 
            .addArgument(this.getWorkflowBaseDir() + pcapPath + "/bin/bammarkduplicates")
            .addArgument("O=" + this.outputPrefix + outputFileName)
            .addArgument("M=" + this.outputPrefix + outputFileName + ".metrics")
            .addArgument("tmpfile=" + this.outputPrefix + outputFileName + ".biormdup")
            .addArgument("markthreads=" + numThreads)
            .addArgument("rewritebam=1 rewritebamlevel=1 index=1 md5=1");
    for (int i = 0; i < numBamFiles; i++) {
    	mergeJob.getCommand().addArgument(" I=firstSlice." + i + ".bam" + " I=secondSlice." + i + ".bam");
    }
    // now compute md5sum for the bai file
    mergeJob.getCommand().addArgument(" && md5sum " + this.outputPrefix + outputFileName + ".bai | awk '{printf $1}'"
        + " > " + this.outputPrefix + outputFileName + ".bai.md5");
    
    for (Job pJob : firstPartJobs) {
    	mergeJob.addParent(pJob);
    }
    mergeJob.setMaxMemory(mergeJobMemG + "000");
    
    // MERGE unmapped reads
    Job mergeUnmappedJob = null;
    if (extract_and_upload_unmapped_reads) {
        mergeUnmappedJob = this.getWorkflow().createBashJob("mergeUnmappedBAM");

        numThreads = 1;
        if (getProperty("numOfThreads") != null && !getProperty("numOfThreads").isEmpty()) {
            numThreads = Integer.parseInt(getProperty("numOfThreads"));
            }
        mergeUnmappedJob.getCommand().addArgument("LD_LIBRARY_PATH=" + this.getWorkflowBaseDir() + pcapPath + "/lib") 
            .addArgument(this.getWorkflowBaseDir() + pcapPath + "/bin/bammarkduplicates")
            .addArgument("O=" + this.outputPrefix + outputUnmappedFileName)
            .addArgument("M=" + this.outputPrefix + outputUnmappedFileName + ".metrics")
            .addArgument("tmpfile=" + this.outputPrefix + outputUnmappedFileName + ".biormdup")
            .addArgument("markthreads=" + numThreads)
            .addArgument("rewritebam=1 rewritebamlevel=1 index=1 md5=1");
        for (int i = 0; i < numBamFiles; i++) {
            mergeUnmappedJob.getCommand().addArgument(" I=unmappedReads1." + i + ".bam" + " I=unmappedReads2." + i + ".bam" + " I=unmappedReads3." + i + ".bam");
        }
        // now compute md5sum for the bai file
        mergeUnmappedJob.getCommand().addArgument(" && md5sum " + this.outputPrefix + outputUnmappedFileName + ".bai | awk '{printf $1}'"
            + " > " + this.outputPrefix + outputUnmappedFileName + ".bai.md5");
        
        for (Job pJob : firstPartUnmappedReadJobs) {
            mergeUnmappedJob.addParent(pJob);
        }
        
        mergeUnmappedJob.setMaxMemory(mergeJobMemG + "000");
    
    }
    
    // CLEANUP ORIGINAL BAM FILES
    for (int i = 0; i < numBamFiles; i++) {
      Job cleanup = this.getWorkflow().createBashJob("cleanup" + i);
      cleanup.getCommand().addArgument("rm -fr " + "firstSlice." + i + ".bam " + "firstSliceOrphaned." + i + ".bam" + "secondSlice." + i + ".bam");
      // cleanup.getCommand().addArgument("ls " + "firstSlice." + i + ".bam " + "firstSliceOrphaned." + i + ".bam" + "secondSlice." + i + ".bam");  // ls only for now, this is for debugging

      // clean up the original downloaded BAMs
      cleanup.getCommand().addArgument(" && rm -f " + bamPaths.get(i));
      // cleanup.getCommand().addArgument(" && ls " + bamPaths.get(i)); // for debugging
      
      if (extract_and_upload_unmapped_reads){
          cleanup.getCommand().addArgument(" && rm -fr " + "unmappedReads1." + i + ".bam " + "unmappedReads2." + i + ".bam " + "unmappedReads3." + i + ".bam");
          // cleanup.getCommand().addArgument(" && ls " + "unmappedReads1." + i + ".bam " + "unmappedReads2." + i + ".bam " + "unmappedReads3." + i + ".bam"); // this is for debugging
          cleanup.addParent(mergeUnmappedJob);
      }
      cleanup.addParent(mergeJob);
      cleanup.setMaxMemory(smallJobMemM);
    }

    // PREPARE METADATA & UPLOAD
    String finalOutDir = this.resultsDir;
    Job bamUploadJob = this.getWorkflow().createBashJob("upload");
    bamUploadJob.getCommand().addArgument("perl " + this.getWorkflowBaseDir() + "/scripts/gnos_upload_data.pl")
            .addArgument("--bam " + this.outputPrefix + outputFileName)
            .addArgument("--bam-md5sum-file " + this.outputPrefix + outputFileName + ".md5")
            .addArgument("--key " + gnosKey)
            .addArgument("--job-description " + this.jobDescription)
            .addArgument("--outdir " + finalOutDir)
            .addArgument("--metadata-urls " + gnosInputMetadataURLs)
            .addArgument("--upload-url " + gnosUploadFileURL);
    
    if (!useGtUpload) {
    	bamUploadJob.getCommand().addArgument("--force-copy");
    }
    if ("true".equals(skipUpload) || !useGtUpload) {
    	bamUploadJob.getCommand().addArgument("--test");
    }
    bamUploadJob.setMaxMemory(gtuploadMemG + "000");
    bamUploadJob.addParent(mergeJob);

    // upload extracted unmapped reads as another GNOS submission
    Job bamUnmappedUploadJob = null;
    if (extract_and_upload_unmapped_reads) {
        bamUnmappedUploadJob = this.getWorkflow().createBashJob("upload");
        bamUnmappedUploadJob.getCommand().addArgument("perl " + this.getWorkflowBaseDir() + "/scripts/gnos_upload_data.pl")
            .addArgument("--bam " + this.outputPrefix + outputUnmappedFileName)
            .addArgument("--bam-md5sum-file " + this.outputPrefix + outputUnmappedFileName + ".md5")
            .addArgument("--key " + gnosKey)
            .addArgument("--job-description " + this.unmappedReadJobDescription)
            .addArgument("--outdir " + finalOutDir)
            .addArgument("--metadata-urls " + gnosInputMetadataURLs)
            .addArgument("--upload-url " + gnosUploadFileURL);
    
        if (!useGtUpload) {
    	    bamUnmappedUploadJob.getCommand().addArgument("--force-copy");
        }
        if ("true".equals(skipUpload) || !useGtUpload) {
    	    bamUnmappedUploadJob.getCommand().addArgument("--test");
        }
        bamUnmappedUploadJob.setMaxMemory(gtuploadMemG + "000");
        bamUnmappedUploadJob.addParent(mergeUnmappedJob);
    }
    
    
    // CLEANUP FINAL BAM
    Job cleanup2 = this.getWorkflow().createBashJob("cleanup2");
    cleanup2.getCommand().addArgument("rm -f " + this.outputPrefix + outputFileName);
    //cleanup2.getCommand().addArgument("ls " + this.outputPrefix + outputFileName); // ls only for now, this is for debugging
    
    if (extract_and_upload_unmapped_reads) {
        cleanup2.getCommand().addArgument(" && rm -f " + this.outputPrefix + outputUnmappedFileName);
        //cleanup2.getCommand().addArgument(" && ls " + this.outputPrefix + outputUnmappedFileName); // ls only for now, this is for debugging
    	cleanup2.addParent(bamUnmappedUploadJob);
    }
    cleanup2.addParent(bamUploadJob);
    cleanup2.setMaxMemory(smallJobMemM);

  }

  
  private Job addDownloadJobArgs (Job job, String file, String fileURL) {

    // a little unsafe
    String[] pathElements = file.split("/");
    String analysisId = pathElements[0];

    if (this.isTesting){ 
        job.getCommand().addArgument(
    		    "mkdir " + analysisId + " && " + "ln -s " + getProperty("testBamPath") + " " + file  // using symlink to avoid copying huge test bam
    		);

    } else {

    	job.getCommand().addArgument("perl " + this.getWorkflowBaseDir() + "/scripts/launch_and_monitor_gnos.pl")
    	    .addArgument("--command 'gtdownload -c " + gnosKey + " -v -d " + fileURL + "'")
            .addArgument("--file-grep " + analysisId)
            .addArgument("--search-path .")
            .addArgument("--retries " + gtdownloadRetries)
            .addArgument("--md5-retries " + gtdownloadMd5Time);
    
    }
    
    return(job);
  }
  
}
