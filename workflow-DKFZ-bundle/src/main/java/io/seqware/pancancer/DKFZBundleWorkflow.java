package io.seqware.pancancer;

import java.io.File;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import net.sourceforge.seqware.pipeline.workflowV2.*;
import net.sourceforge.seqware.pipeline.workflowV2.model.*;
import java.util.*;
import java.util.logging.*;

/**
 * This is the DKFZ seqware workflow which hosts and calls several workflows: - DKFZ SNV Calling - DKFZ Indel Calling - DKFZ Copy number estimation
 *
 * All workflows themselves are implemented in such a way that they use SGE directly to run their jobs.
 *
 * All workflows basically rely on two merged bam (control and tumor sample) files as input files. In addition, the copy number estimation workflow needs input files from EMBL's delly workflow.
 */
public class DKFZBundleWorkflow extends AbstractWorkflowDataModel {

  Logger logger = Logger.getLogger(DKFZBundleWorkflow.class.getName());

  // datetime all upload files will be named with
  DateFormat df = new SimpleDateFormat("yyyyMMdd");
  String dateString = df.format(Calendar.getInstance().getTime());

  private String workflowName = "dkfz_1-0-0";
  
  // comma-seperated for multiple bam inputs
  // used to download with gtdownload
  ArrayList<String> inputMetadataURLs = new ArrayList<String>();

  String gnosInputMetadataURLs = null;
  String gnosUploadFileURL = null;

  String inputFileTumorSpecimenUuid = null;
  String inputFileControlSpecimenUuid = null;
  
  // Input parameters and files
  String pid;

  File directoryBaseOutput = null;
  File directoryBundledFiles = null;

  File gnosDownloadDirGeneric = null;
  File gnosUploadDir = null;

  File processDirectoryPID = null;
  File directoryAlignmentFiles = null;
  File directoryDellyFiles = null;
  File directorySNVCallingResults = null;
  File directoryIndelCallingResults = null;
  File directoryCNEResults = null;

  String gnosKey = null;

  // GTDownload settings
  String gtdownloadRetries = "30";
  String gtdownloadMd5Time = "120";
  String gtdownloadMem = "8";
  String smallJobMemM = "3000";

  String inputFileTumorURL = null;
  String inputFileNormalURL = null;
  String inputFileDependenciesURL = null;
  String inputFileDellyURL = null;

  File inputFileTumor = null;
  File inputFileNormal = null;
  File inputFileDependencies = null;
  File inputFileDelly = null;

  File outputFileSNVCallingVCFRaw = null;
  File outputFileSNVCallingVCF = null;
  File outputFileIndelCallingVCFRaw = null;
  File outputFileIndelCallingVCF = null;
  File outputFileCNEVCF = null;
  File outputFileCNETarball = null;

  // Run flags
  boolean debugmode = false;

  boolean useGtDownload = true;
  boolean useGtUpload = true;

  boolean doCleanup = false;
  boolean doSNVCalling = false;
  boolean doIndelCalling = false;
  boolean doCopyNumberEstimation = false;
  boolean useDellyOnDisk = false;

  /**
   * Safely load a property from seqwares workflow environment.
   *
   * @param id
   * @param _default
   * @return
   */
  private String loadProperty(String id, String _default) {
    try {
      String res = getProperty(id);
      return res == null ? _default : res;
    } catch (Exception ex) {
      return _default;
    }
  }

  private boolean loadBooleanProperty(String id) {
    return loadBooleanProperty(id, false);
  }

  /**
   * Safely load a boolean property from the configuration
   */
  private boolean loadBooleanProperty(String id, boolean _default) {
    try {
      return "true".equals(getProperty(id));
    } catch (Exception ex) {
      return _default;
    }
  }

  /**
   * This workflow isn't using file provisioning since we're using GeneTorrent. So this method is just being used to setup various variables.
   */
  @Override
  public Map<String, SqwFile> setupFiles() {

    try {

      pid = loadProperty("pid", null);
      debugmode = loadBooleanProperty("debug_mode", debugmode);

      String outputdir = debugmode ? "testdata" : getProperty("output_dir");

      directoryBaseOutput = new File(getProperty("output_prefix"));

      gnosDownloadDirGeneric = new File(directoryBaseOutput, "gnos_download");
      directoryBundledFiles = new File(directoryBaseOutput, "bundledFiles");
      
      inputFileTumorSpecimenUuid = getProperty("input_file_tumor_specimen_uuid");
      inputFileControlSpecimenUuid = getProperty("input_file_control_specimen_uuid");

      processDirectoryPID = new File(new File(directoryBaseOutput, outputdir), pid);
      directoryAlignmentFiles = new File(processDirectoryPID, "alignment");
      directoryDellyFiles = new File(processDirectoryPID, "delly");
      directorySNVCallingResults = new File(processDirectoryPID, "mpileup");
      directoryIndelCallingResults = new File(processDirectoryPID, "platypus_indel");
      directoryCNEResults = new File(processDirectoryPID, "ACEseq_dbg");

      gnosInputMetadataURLs = getProperty("gnos_input_metadata_urls");
      for (String url : gnosInputMetadataURLs.split(",")) {
        inputMetadataURLs.add(url);
      }

      gnosUploadFileURL = getProperty("gnos_output_file_url");
      gnosKey = getProperty("gnos_key");
      gnosUploadDir = new File(directoryBaseOutput, "gnos_upload");

      doCleanup = loadBooleanProperty("clean_up");
      doSNVCalling = loadBooleanProperty("snv_calling");
      doIndelCalling = loadBooleanProperty("indel_calling");
      doCopyNumberEstimation = loadBooleanProperty("ace_seq");

      inputFileNormalURL = getProperty("input_file_control");
      inputFileTumorURL = getProperty("input_file_tumor");
      inputFileDependenciesURL = getProperty("input_file_dependencies");
      if (doCopyNumberEstimation) {
        inputFileDellyURL = loadProperty("input_file_dependencies", null);
        useDellyOnDisk = loadBooleanProperty("useDellyFileFromDisk", false);
        inputFileDelly = new File(directoryDellyFiles, pid + ".DELLY.somaticFilter.highConf.bedpe.txt");
      }

      useGtDownload = !"false".equals(getProperty("use_gtdownload"));
      useGtUpload = !"false".equals(getProperty("use_gtupload"));

      gtdownloadRetries = loadProperty("gtdownloadRetries", gtdownloadRetries);
      gtdownloadMd5Time = loadProperty("gtdownloadMd5time", gtdownloadMd5Time);
      gtdownloadMem = loadProperty("gtdownloadMemG", gtdownloadMem);
      smallJobMemM = loadProperty("smallJobMemM", smallJobMemM);

      System.out.println("" + doCleanup + " " + doSNVCalling + " " + doIndelCalling + " " + doCopyNumberEstimation);

    } catch (Exception e) {
      Logger.getLogger(DKFZBundleWorkflow.class.getName()).log(Level.SEVERE, null, e);
      //throw new RuntimeException("Problem parsing variable values: " + e.getMessage());
    }

    return this.getFiles();
  }

  @Override
  public void setupDirectory() {
  }

  /**
   * Shortcut for createRoddyJob with a default runMode of "run"
   */
  private Job createRoddyJob(String name, String pid, String configuration, List<Job> parentJobs) {
    return createRoddyJob(name, pid, configuration, parentJobs, "run");
  }

  /**
   * Create job which calls the Roddy workflow environment.
   *
   * To allow dependencies on Roddy jobs, Roddy is called with the --waitforjobs option.
   *
   * Roddy itself calls a range of SGE jobs and waits for those jobs to finish. The return code of Roddy is either 0 (0 faulty jobs) or n (1 .. n faulty jobs).
   *
   * @param name The name for the job
   * @param pid The pid of the dataset to process
   * @param analysisConfigurationID The configuration which will be used for the process
   * @param parentJobs A list of parent jobs which preceed this job.
   * @param runMode The runmode which is i.e. run / rerun / testrun.
   * @return
   */
  private Job createRoddyJob(String name, String pid, String analysisConfigurationID, List<Job> parentJobs, String runMode) {
    Job job = this.getWorkflow().createBashJob(name);
    job.setMaxMemory("16384");
    for (Job parentJob : parentJobs) {
      job.addParent(parentJob);
    }
    String fullConfiguration = "dkfzPancancerBase" + (debugmode ? ".dbg" : "") + "@" + analysisConfigurationID;
    // TODO: this needs to be parameterized I think if we can't bundle Roddy
    job.getCommand()
      .addArgument("cd " + this.getWorkflowBaseDir() + "/bin/RoddyBundlePancancer") 
      .addArgument(String.format(" && bash roddy.sh %s %s %s --useconfig=applicationPropertiesAllLocal.ini --waitforjobs", runMode, fullConfiguration, pid));
    if (debugmode) {
      job.getCommand().addArgument(" --verbositylevel=5 ");
    }
    job.getCommand().addArgument(String.format("  &> %s/roddy_%s.txt ", directorySNVCallingResults, name));
    return job;
  }

  /**
   * Create a default job for GNOS Up or Download
   *
   * @param name
   * @param parent
   * @return
   */
  private Job createDefaultGNOSJob(String name, Job parent) {
    Job job = this.getWorkflow().createBashJob(name);
    job.setMaxMemory(gtdownloadMem + "000");
    job.addParent(parent);
    return job;
  }

  /**
   * Creates the arguments for a call to the GNOS download script.
   *
   * @param job
   * @param fileURL
   * @param targetDirectory
   * @param elementID
   * @return
   */
  private Job addGNOSDownloadScriptArgs(Job job, String fileURL, File targetDirectory, String elementID) {
    String lockfile = getLockfileNameForGNOSDownload(targetDirectory, elementID);
    String checkpointFile = String.format("%s/%s/download_checkpoint.txt", targetDirectory, elementID);
    job.getCommand()
      .addArgument(
        String.format("lockfile %s; ", lockfile)
        + String.format("[[ ! -f %s ]] && ", checkpointFile)
        + String.format("perl %s/scripts/launch_and_monitor_gnos.pl ", this.getWorkflowBaseDir())
        + String.format("--command 'gtdownload -c %s -d %s -p %s ' ", gnosKey, fileURL, targetDirectory)
        + String.format("--file-grep %s --search-path %s --retries %s --md5-retries %s ", elementID, targetDirectory, gtdownloadRetries, gtdownloadMd5Time)
        + String.format(" && touch %s; ", checkpointFile)
        + String.format("rm -rf %s; ", lockfile)
      );
    return job;
  }

  private String getLockfileNameForGNOSDownload(File targetDirectory, String elementID) {
    String lockfile = new File(targetDirectory, "gnosDownload_" + elementID + ".lock~").getAbsolutePath();
    return lockfile;
  }

  /**
   * Extract the uuid of an object from its url. Example: https://gtrepo-dkfz.annailabs.com/cghub/metadata/analysisFull/174bdd2d-1810-4890-af87-8aef4827eb3c => 174bdd2d-1810-4890-af87-8aef4827eb3c
   *
   * @param url
   * @return
   */
  private String getElementIDFromURL(String url) {
    logger.log(Level.INFO, "getElementIDFromURL {0} {1}", new Object[]{url, url.split("/").length});
    String[] urlElements = url.split("/");
    return urlElements[urlElements.length - 1];
  }

  /**
   * Creates a default range of parameters for a GNOS download job.
   *
   * @param parent
   * @param fileURL
   * @param targetDirectory
   * @return
   */
  private CreateDownloadJobResult createDefaultGNOSDownloadJob(Job parent, String fileURL, File targetDirectory) {
    String elementID = getElementIDFromURL(fileURL);
    Job job = createDefaultGNOSJob("GNOS download job", parent);
    File outputDirectory = new File(targetDirectory, elementID);
    addGNOSDownloadScriptArgs(job, fileURL, targetDirectory, elementID);
    return new CreateDownloadJobResult(job, elementID, outputDirectory);
  }

  /**
   * Link a file safely to the file system.
   *
   * @param job
   * @param src
   * @param dst
   */
  private void addSafeLinkCommand(Job job, String src, String dst) {
    String lockfile = dst + ".lock~";
    job.getCommand().addArgument(String.format("lockfile %s; [[ ! -f %s ]] && ln -sn %s %s; rm -rf %s; ", lockfile, dst, src, dst, lockfile));
  }

  private Job createGNOSBamDownloadJob(String fileURL, SampleType sampleType, Job parent) {
    CreateDownloadJobResult jcr = createDefaultGNOSDownloadJob(parent, fileURL, gnosDownloadDirGeneric);

    String bamSrc = String.format("%s/*.bam", jcr.outputDirectory);
    String bamDst = String.format("%s/%s_%s_merged.mdup.bam", directoryAlignmentFiles, sampleType.name(), pid);
    String baiSrc = bamSrc + ".bai";
    String baiDst = bamDst + ".bai";
    addSafeLinkCommand(jcr.job, bamSrc, bamDst);
    addSafeLinkCommand(jcr.job, baiSrc, baiDst);
    return jcr.job;
  }

  private Job createGNOSDellyDownloadJob(String fileURL, Job parent) {
    CreateDownloadJobResult jcr = createDefaultGNOSDownloadJob(parent, fileURL, gnosDownloadDirGeneric);

    String dellySrc = String.format("%s/*.txt", jcr.outputDirectory);
    String dellyDst = String.format("%s/%s.DELLY.somaticFilter.highConf.bedpe.txt", directoryDellyFiles, pid);
    addSafeLinkCommand(jcr.job, dellySrc, dellyDst);
    return jcr.job;
  }

  private Job createDependenciesDownloadJob(String fileURL, Job parent) {
    // TODO: would be nice to download this just once and skip in future runs if that download directory exists
    CreateDownloadJobResult jcr = createDefaultGNOSDownloadJob(parent, fileURL, gnosDownloadDirGeneric);
    String lockfile = getLockfileNameForGNOSDownload(gnosDownloadDirGeneric, jcr.elementID);
    String extractedDirectory = jcr.outputDirectory + "/bundledFiles";
    jcr.job.getCommand().addArgument(
      String.format("lockfile %s; [[ ! -d %s ]] && cd %s && tar -xf *.tar.gz && ln -sf %s %s; rm -rf %s; ", lockfile, jcr.outputDirectory + "/bundledFiles", jcr.outputDirectory, extractedDirectory, directoryBaseOutput, lockfile)
    );
    return jcr.job;
  }

  private Job createGNOSUploadJob(String name, File file, Job parent) {
    Job job = createDefaultGNOSJob(name, parent);
    addUploadJobArgs(job, file);
    return job;
  }

  @Override
  public void buildWorkflow() {
    try {
      boolean runAtLeastOneJob = true;//doSNVCalling && doIndelCalling & doCopyNumberEstimation;

            // the download jobs that either downloads or locates the file on the filesystem
      // download the normal and tumor bamfile and the dependencies jar
      Job jobDownloadTumorBam = null;
      Job jobDownloadControlBam = null;
      Job jobDownloadDellyBedPe = null;
      Job jobDownloadWorkflowDependencies = null;
      Job createDirs = this.getWorkflow().createBashJob("CreateDirs");
      if (runAtLeastOneJob) {
        List<File> processDirectories = Arrays.asList(gnosDownloadDirGeneric, directoryAlignmentFiles, directoryDellyFiles, directorySNVCallingResults, directoryIndelCallingResults, directoryCNEResults);
        StringBuilder createDirArgs = new StringBuilder();
        for (File processDirectory : processDirectories) {
          createDirArgs.append("mkdir -p ").append(processDirectory.getAbsolutePath()).append(";");
        }
        createDirs.getCommand().addArgument(createDirArgs.toString());

        if (useGtDownload) {
          jobDownloadWorkflowDependencies = createDependenciesDownloadJob(inputFileDependenciesURL, createDirs);
          jobDownloadTumorBam = createGNOSBamDownloadJob(inputFileTumorURL, SampleType.tumor, createDirs);
          jobDownloadControlBam = createGNOSBamDownloadJob(inputFileNormalURL, SampleType.control, createDirs);
          if (doCopyNumberEstimation && !useDellyOnDisk) {
            jobDownloadDellyBedPe = createGNOSDellyDownloadJob(inputFileDellyURL, createDirs);
          }
        }
      }

      // Create job variables
      Job jobSNVCalling;
      Job jobIndelCalling = null;
      Job jobCopyNumberEstimationFinal = null;
      List<Job> downloadJobDependencies = new LinkedList<Job>();
      for (Job job : Arrays.asList(jobDownloadControlBam, jobDownloadTumorBam, jobDownloadWorkflowDependencies)) {
        if (job == null) {
          continue;
        }
        downloadJobDependencies.add(job);
      }
      //If no download was started, add at least createdirs.
      if (downloadJobDependencies.size() == 0) {
        downloadJobDependencies.add(createDirs);
      }

      // source, index, md5sum, destination vcf, destination index, destination md5sum
      ArrayList<ArrayList<String>> vcfFiles = new ArrayList<ArrayList<String>>();
      
      
      if (doSNVCalling) {
        logger.info("SNV Calling will be done.");
        jobSNVCalling = createRoddyJob("RoddySNVCalling", pid, "snvCalling", downloadJobDependencies);
//                createGNOSUploadJob("GNOSUpload Raw VCF SNVCalling", new File(directorySNVCallingResults, "snvs_" + pid + "_raw.vcf.gz"), jobSNVCalling);
//                createGNOSUploadJob("GNOSUpload VCF SNVCalling", new File(directorySNVCallingResults, "snvs_" + pid + ".vcf.gz"), jobSNVCalling);
        ArrayList<String> curr = new ArrayList<String>();
        // files
        curr.add(new File(directorySNVCallingResults, "snvs_" + pid + ".vcf.gz").getAbsolutePath());
        curr.add(new File(directorySNVCallingResults, "snvs_" + pid + ".vcf.gz.tbi").getAbsolutePath());
        curr.add(new File(directorySNVCallingResults, "snvs_" + pid + ".vcf.gz.md5").getAbsolutePath());
        // output names
        // pid is the name of the sample
        curr.add(inputFileTumorSpecimenUuid + "." + this.workflowName + "." + this.dateString + ".somatic.snv_mnv.vcf.gz");
        curr.add(inputFileTumorSpecimenUuid + "." + this.workflowName + "." + this.dateString + ".somatic.snv_mnv.vcf.gz.tbi");
        curr.add(inputFileTumorSpecimenUuid + "." + this.workflowName + "." + this.dateString + ".somatic.snv_mnv.vcf.gz.md5");

        // LEFT OFF WITH: need to check if I need the md5 sum of the tbi files too
        // need to add Keiran's upload wrapper script and the updated VCF uploader
        

      }

      if (doIndelCalling) {
        logger.info("Indel Calling will be done.");
        jobIndelCalling = createRoddyJob("RoddyIndelCalling", pid, "indelCalling", downloadJobDependencies);
//                createGNOSUploadJob("GNOSUpload Raw VCF IndelCalling", new File(directoryIndelCallingResults, "indels_" + pid + "_raw.vcf.gz"), jobIndelCalling);
//                createGNOSUploadJob("GNOSUpload VCF IndelCalling", new File(directoryIndelCallingResults, "indels_" + pid + ".vcf.gz"), jobIndelCalling);
      }

      if (jobDownloadDellyBedPe != null) {
        downloadJobDependencies.add(jobDownloadDellyBedPe);
      }

      if (doCopyNumberEstimation) {
        logger.info("Copy number estimation will be done.");
        Job jobCopyNumberEstimation = createRoddyJob("RoddyCNE", pid, "copyNumberEstimation", downloadJobDependencies);
        //createGNOSUploadJob("GNOSUpload VCF Copy Number Estimation", new File(directoryCNEResults, "snvs_" + pid + ".vcf.gz"), jobCopyNumberEstimationFinal);
        //TODO Create additional files upload job.
        //Upload all vcfs + tabix files
        //Upload a tarball
      }

            // CLEANUP DOWNLOADED INPUT BAM FILES (And intermediate files?)
		   /* if (doCleanup) {
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
       }*/
    } catch (Exception ex) {
      Logger.getLogger(DKFZBundleWorkflow.class.getName()).log(Level.SEVERE, "Problem running workflow", ex);
      //throw new RuntimeException("Problem parsing variable values: " + e.getMessage());
    }
  }

  private Job addUploadJobArgs(Job job, File file) {
    String path = file.getParent();
    String md5File = file.getAbsolutePath() + ".md5";
    logger.log(Level.INFO, "Switching to path {0}", path);

    job.getCommand().addArgument(String.format(" cd %s && md5sum %s | awk '{printf $1}' > %s ;", path, file, md5File));
    job.getCommand()
      .addArgument("perl " + this.getWorkflowBaseDir() + "/scripts/gnos_upload_data.pl")
      .addArgument("--bam " + directorySNVCallingResults + "/" + file)
      .addArgument("--key " + gnosKey)
      .addArgument("--outdir " + gnosUploadDir.getAbsolutePath())
      .addArgument("--metadata-urls " + gnosInputMetadataURLs)
      .addArgument("--upload-url " + gnosUploadFileURL)
      .addArgument("--bam-md5sum-file " + md5File);
    if (debugmode) {
      job.getCommand().addArgument("--test");
    }

    return (job);
  }

}
