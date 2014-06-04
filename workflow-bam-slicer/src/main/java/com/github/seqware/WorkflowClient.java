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
  boolean useGtDownload = true;
  boolean useGtUpload = true;
  boolean isTesting = true;

  String outputDir = "results";
  String outputPrefix = "./";
  String resultsDir = outputPrefix + outputDir;
  
  String outputFileName = "merged_output.bam";
  
  String sortJobMemG = "8";

  String skipUpload = null;

  String pcapPath = "/bin/PCAP-core-1.0.4";
  
  // GTDownload
  // each retry is 1 minute
  String gtdownloadRetries = "30";
  String gtdownloadMd5Time = "120";
  String gtdownloadMemG = "8";
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

      skipUpload = getProperty("skip_upload") == null ? "true" : getProperty("skip_upload");
      gtdownloadRetries = getProperty("gtdownloadRetries") == null ? "30" : getProperty("gtdownloadRetries");
      gtdownloadMd5Time = getProperty("gtdownloadMd5time") == null ? "120" : getProperty("gtdownloadMd5time");
      
      gtdownloadMemG = getProperty("gtdownloadMemG") == null ? "8" : getProperty("gtdownloadMemG");
      smallJobMemM = getProperty("smallJobMemM") == null ? "2000" : getProperty("smallJobMemM");
      sortJobMemG = getProperty("sortJobMemG") == null ? "8" : getProperty("sortJobMemG");
      
      if (getProperty("use_gtdownload") != null && "false".equals(getProperty("use_gtdownload"))) { useGtDownload = false; }
      if (getProperty("use_gtupload") != null && "false".equals(getProperty("use_gtupload"))) { useGtUpload = false; }
      if (getProperty("isTesting") != null && "false".equals(getProperty("isTesting"))) { isTesting = false; }

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
      headerJob.setMaxMemory("2000");

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
    Job mergeSortJob = this.getWorkflow().createBashJob("mergeBAM");

    int numThreads = 1;
    if (getProperty("numOfThreads") != null && !getProperty("numOfThreads").isEmpty()) {
      numThreads = Integer.parseInt(getProperty("numOfThreads"));
    }
    mergeSortJob.getCommand().addArgument("LD_LIBRARY_PATH=" + this.getWorkflowBaseDir() + pcapPath + "/lib") 
            .addArgument(this.getWorkflowBaseDir() + pcapPath + "/bin/bammarkduplicates")
            .addArgument("O=" + this.outputPrefix + outputFileName)
            .addArgument("M=" + this.outputPrefix + outputFileName + ".metrics")
            .addArgument("tmpfile=" + this.outputPrefix + outputFileName + ".biormdup")
            .addArgument("markthreads=" + numThreads)
            .addArgument("rewritebam=1 rewritebamlevel=1 index=1 md5=1");
    for (int i = 0; i < numBamFiles; i++) {
    	mergeSortJob.getCommand().addArgument(" I=firstSlice." + i + ".bam" + " I=secondSlice." + i + ".bam");
    }
    for (Job pJob : firstPartJobs) {
    	mergeSortJob.addParent(pJob);
    }

    mergeSortJob.setMaxMemory(sortJobMemG + "000");
    
    // CLEANUP ORIGINAL BAM FILES
    for (int i = 0; i < numBamFiles; i++) {
      Job cleanup = this.getWorkflow().createBashJob("cleanup" + i);
      //cleanup.getCommand().addArgument("rm -fr " + "firstSlice" + i + ".bam " + "secondSlice" + i + ".bam");
      cleanup.getCommand().addArgument("touch " + "firstSlice" + i + ".bam " + "secondSlice" + i + ".bam");  // touch only for now
      cleanup.addParent(mergeSortJob);
      cleanup.setMaxMemory(smallJobMemM);
    }

    // PREPARE METADATA & UPLOAD
    String finalOutDir = this.resultsDir;
    Job bamUploadJob = this.getWorkflow().createBashJob("upload");
    bamUploadJob.getCommand().addArgument("perl " + this.getWorkflowBaseDir() + "/scripts/gnos_upload_data.pl")
            .addArgument("--bam " + this.outputPrefix + outputFileName)
            .addArgument("--key " + gnosKey)
            .addArgument("--outdir " + finalOutDir)
            .addArgument("--metadata-urls " + gnosInputMetadataURLs)
            .addArgument("--upload-url " + gnosUploadFileURL)
            .addArgument("--bam-md5sum-file " + this.outputPrefix + outputFileName + ".md5");
    
    if (!useGtUpload) {
    	bamUploadJob.getCommand().addArgument("--force-copy");
    }
    if ("true".equals(skipUpload) || !useGtUpload) {
    	bamUploadJob.getCommand().addArgument("--test");
    }
    bamUploadJob.setMaxMemory(smallJobMemM);
    bamUploadJob.addParent(mergeSortJob);
    
    // CLEANUP FINAL BAM
    Job cleanup2 = this.getWorkflow().createBashJob("cleanup2");
    //cleanup3.getCommand().addArgument("rm -f " + this.outputPrefix + outputFileName);
    cleanup2.getCommand().addArgument("touch " + this.outputPrefix + outputFileName); // touch only for now
    cleanup2.addParent(bamUploadJob);
    cleanup2.setMaxMemory(smallJobMemM);

  }

  
  private Job addDownloadJobArgs (Job job, String file, String fileURL) {

    // a little unsafe
    String[] pathElements = file.split("/");
    String analysisId = pathElements[0];

    job.getCommand().addArgument(
    		this.isTesting ?
    		    "mkdir " + analysisId + " && " + "ln -s " + getProperty("testBamPath") + " " + file :  // using symlink to avoid copying huge test bam
    		    "gtdownload -c "+gnosKey+" -v -d "+ fileURL
    		);


    /*
    job.getCommand().addArgument("perl " + this.getWorkflowBaseDir() + "/scripts/launch_and_monitor_gnos.pl")
    .addArgument("--command 'gtdownload -c "+gnosKey+" -v -d "+fileURL+"'")
    .addArgument("--file-grep "+analysisId)
    .addArgument("--search-path .")
    .addArgument("--retries "+gtdownloadRetries)
    .addArgument("--md5-retries "+gtdownloadMd5Time);
    */
    
    return(job);
  }
  
}
