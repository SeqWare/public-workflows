package io.seqware.pancancer;

import net.sourceforge.seqware.pipeline.workflowV2.*;
import net.sourceforge.seqware.pipeline.workflowV2.model.*;
import java.util.*;
import java.util.logging.*;

/**
 * This is the DKFZ seqware workflow which hosts and calls several workflows:
 * - DKFZ SNV Calling
 * - DKFZ Indel Calling
 * - DKFZ Copy number estimation
 *
 * All workflows themselves are implemented in such a way that they use SGE directly to run their jobs.
 *
 * All workflows basically rely on two merged bam (control and tumor sample) files as input files. In addition, the copy number estimation workflow needs input files from EMBL's delly workflow.
 */
public class DKFZBundleWorkflow extends AbstractWorkflowDataModel {
	
    // comma-seperated for multiple bam inputs
    // used to download with gtdownload
    ArrayList<String> inputMetadataURLs = new ArrayList<String>();
    String gnosInputMetadataURLs = null;

    String gnosUploadFileURL = null;
    String gnosUploadDir = null;
    String gnosDownloadDirGeneric = null;
    String gnosDownloadDirSpecific = null;
    //String gnosOutputDir = null;
    String directoryAlignmentFiles = null;
    String directoryDellyFiles = null;
    String directorySNVCallingResults = null;
    String directoryIndelCallingResults = null;
    String directoryCNEResults = null;
    String directoryBundledFiles = null;
    
    List<String> processDirectories = Arrays.asList(gnosDownloadDirGeneric, gnosDownloadDirSpecific, directoryAlignmentFiles, directoryDellyFiles, directorySNVCallingResults, directoryIndelCallingResults, directoryCNEResults);

    String gnosKey = null;
    //String outputdir = null;
    String directoryBaseOutput = null;

    // GTDownload settings
    String gtdownloadRetries = "30";
    String gtdownloadMd5Time = "120";
    String gtdownloadMem = "8";
    String smallJobMemM = "3000";

	// Input parameters and files
	String pid;
	
    String inputFileTumorURL = null;
    String inputFileNormalURL = null;
    String inputFileDependenciesURL = null;
    String inputFileDellyURL = null;

    String inputFileTumor = null;
    String inputFileNormal = null;
    String inputFileDependencies = null;
    String inputFileDelly = null;


	// Run flags
    boolean useGtDownload = true;
    boolean useGtUpload = true;

    boolean debugmode = false;
    boolean doCleanup = false;
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

	/**
	 * This workflow isn't using file provisioning since we're using
	 * GeneTorrent. So this method is just being used to setup various
	 * variables.
	 */
    @Override
    public Map<String, SqwFile> setupFiles() {

        try {

            pid = getProperty("pid");

            debugmode = "true".equals(getProperty("debug_mode"));
            String outputdir = getProperty("output_dir");
            if (debugmode) outputdir = "testdata";
            directoryBaseOutput = getProperty("output_prefix");

			String outputBaseDir = String.format("%s/%s/%s", directoryBaseOutput, outputdir, pid);
			
            gnosDownloadDirGeneric = String.format("%s/%s/gnosDownload", getProperty("output_prefix"), outputdir);
            gnosDownloadDirSpecific = outputBaseDir + "/gnosDownload";
            directoryBundledFiles = directoryBaseOutput + "/bundledFiles";
            
			directoryAlignmentFiles = String.format("%s/alignment", outputBaseDir);
            directoryDellyFiles = String.format("%s/delly", outputBaseDir);
            directorySNVCallingResults = String.format("%s/mpileup", outputBaseDir);
            directoryIndelCallingResults = String.format("%s/platypus_indel", outputBaseDir);
            directoryCNEResults = String.format("%s/ACEseq_dbg", outputBaseDir); 

            gnosInputMetadataURLs = getProperty("gnos_input_metadata_urls");
            for (String url : gnosInputMetadataURLs.split(",")) {
                inputMetadataURLs.add(url);
            }

            gnosUploadFileURL = getProperty("gnos_output_file_url");
            gnosKey = getProperty("gnos_key");
            gnosUploadDir = getProperty("gnos_upload_dir");

            doCleanup = "true".equals(getProperty("clean_up"));
            doSNVCalling = "true".equals(getProperty("snv_calling"));
            doIndelCalling = "true".equals(getProperty("indel_calling"));
            doCopyNumberEstimation = "true".equals(getProperty("ace_seq"));

            inputFileNormalURL = getProperty("input_file_control");
            inputFileTumorURL = getProperty("input_file_tumor");
            inputFileDependenciesURL = getProperty("input_file_dependencies");
            if (doCopyNumberEstimation) inputFileDellyURL = loadProperty("input_file_dependencies", null);

            useGtDownload = !"false".equals(getProperty("use_gtdownload"));
            useGtUpload = !"false".equals(getProperty("use_gtupload"));

            gtdownloadRetries = loadProperty("gtdownloadRetries", gtdownloadRetries);
            gtdownloadMd5Time = loadProperty("gtdownloadMd5time", gtdownloadMd5Time);
            gtdownloadMem = loadProperty("gtdownloadMemG", gtdownloadMem);
            smallJobMemM = loadProperty("smallJobMemM", smallJobMemM);

        } catch (Exception e) {
            Logger.getLogger(DKFZBundleWorkflow.class.getName()).log(Level.SEVERE, null, e);
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
        job.getCommand()
			.addArgument("cd " + this.getWorkflowBaseDir() + "/RoddyBundlePancancer")
            .addArgument(String.format(" && bash roddy.sh %s %s %s --useconfig=applicationPropertiesAllLocal.ini --waitforjobs ", runMode, fullConfiguration, pid));
        if (debugmode)
            job.getCommand().addArgument("--verbositylevel=5 ");
        return job;
    }

	private Job createDefaultGNOSJob(String name, Job parent) {
        Job job = this.getWorkflow().createBashJob(name);
        job.setMaxMemory(gtdownloadMem + "000");
        job.addParent(parent);
        return job;
	}
		
	private Job addGNOSDownloadScriptArgs(Job job, String fileURL, String targetDirectory, String elementID) {
        job.getCommand()
                .addArgument(
					String.format("lockfile %s.lock; ", targetDirectory) +
					String.format("perl %s/scripts/launch_and_monitor_gnos.pl ", this.getWorkflowBaseDir()) + 
					String.format("--command 'gtdownload -c %s -d %s -p %s ' ", gnosKey, fileURL, targetDirectory) +
					String.format("--file-grep %s --search-path . --retries %s --md5-retries %s; ", elementID, gtdownloadRetries, gtdownloadMd5Time) +
					String.format("rm -rf %s.lock; ", targetDirectory)
				);
		return job;
	}
   
    private String getElementIDFromURL(String url) {
		String[] urlElements = url.split("/");
		return urlElements[urlElements.length - 1];
	}
  
	private CreateDownloadJobResult createDefaultGNOSDownloadJob(Job parent, String fileURL, String targetDirectory) {
		String elementID = getElementIDFromURL(fileURL);
		Job job = createDefaultGNOSJob("GNOS download job", parent);
		String outputDirectory = targetDirectory + "/" + elementID;
        addGNOSDownloadScriptArgs(job, fileURL, outputDirectory, elementID);
        return new CreateDownloadJobResult(job, elementID, outputDirectory);
	}
	
	private void addSafeLinkCommand(Job job, String src, String dst) {
		String lockfile = dst + ".lock~";
		job.getCommand().addArgument(String.format("lockfile %s; [[ ! -f %s ]] && ln -sn %s %s; rm -rf %s; ", lockfile, dst, src, dst, lockfile));
	}
  
    private Job createGNOSBamDownloadJob(String fileURL, SampleType sampleType, Job parent) {
		CreateDownloadJobResult jcr = createDefaultGNOSDownloadJob(parent, fileURL, gnosDownloadDirSpecific);
	
		String bamSrc = String.format("%s/*.bam", jcr.outputDirectory);
		String bamDst = String.format("%s/%s_%s_merged.mdup.bam", directoryAlignmentFiles, sampleType.name(), pid);
		String baiSrc = bamSrc + ".bai";
		String baiDst = bamDst + ".bai"; 
		addSafeLinkCommand(jcr.job, bamSrc, bamDst);
		addSafeLinkCommand(jcr.job, baiSrc, baiDst);
        return jcr.job;
    }
    
    private Job createGNOSDellyDownloadJob(String fileURL, Job parent) {
		CreateDownloadJobResult jcr = createDefaultGNOSDownloadJob(parent, fileURL, gnosDownloadDirSpecific);

		String dellySrc = String.format("%s/*.txt", jcr.outputDirectory);
		String dellyDst = String.format("%s/%s.DELLY.somaticFilter.highConf.bedpe.txt", directoryDellyFiles, pid);
		addSafeLinkCommand(jcr.job, dellySrc, dellyDst);
		return jcr.job;
	}
    
    private Job createDependenciesDownloadJob(String fileURL, Job parent) {
		CreateDownloadJobResult jcr = createDefaultGNOSDownloadJob(parent, fileURL, gnosDownloadDirGeneric);

		String tarFile = directoryBaseOutput + "/workflow-dependencies.tar.gz";
		String extractedDirectory = directoryBaseOutput + "/bundledFiles";
		String lockfile = tarFile + ".lock~";
		jcr.job.getCommand().addArgument(
					String.format("lockfile %s; [[ ! -d %s ]] && cd %s && tar -xf *.tar.gz && ln -sf bundledFiles %s; rm -rf %s; ", lockfile, jcr.outputDirectory, directoryBaseOutput, lockfile)
				);
		return jcr.job;
	}

    private Job createGNOSUploadJob(String name, String file, Job parent) {
        Job job = createDefaultGNOSJob(name, parent);
        addUploadJobArgs(job, file);
        return job;
    }

    @Override
    public void buildWorkflow() {
        boolean runAtLeastOneJob = doSNVCalling & doIndelCalling & doCopyNumberEstimation;

        // the download jobs that either downloads or locates the file on the filesystem
        // download the normal and tumor bamfile and the dependencies jar
        Job jobDownloadTumorBam = null;
        Job jobDownloadControlBam = null;
        Job jobDownloadDellyBedPe = null;
        Job jobDownloadWorkflowDependencies = null;
        if (runAtLeastOneJob) {
            Job createDirs = this.getWorkflow().createBashJob("CreateDirs");
            StringBuffer createDirArgs = new StringBuffer();
            for(String processDirectory : processDirectories)
				createDirArgs.append("mkdir -p ").append(processDirectory).append(";");
			createDirs.getCommand().addArgument(createDirArgs.toString());
			
            jobDownloadTumorBam = createGNOSBamDownloadJob(inputFileTumorURL, SampleType.tumor, createDirs);
            jobDownloadControlBam = createGNOSBamDownloadJob(inputFileNormalURL, SampleType.control, createDirs);
            jobDownloadDellyBedPe = createGNOSDellyDownloadJob(inputFileDellyURL, createDirs);
            jobDownloadWorkflowDependencies = createDependenciesDownloadJob(inputFileDependenciesURL, createDirs);
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
            createGNOSUploadJob("GNOSUpload VCF Copy Number Estimation", "snvs_" + pid + ".vcf.gz", jobCopyNumberEstimationFinal);
            //TODO Create additional files upload job.
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
    }

	

    private Job addUploadJobArgs(Job job, String file) {

        job.getCommand()
                .addArgument(String.format(" cd %s && md5sum %s | awk '{printf $1}' > %s.md5 ;", directorySNVCallingResults, file, file));

        job.getCommand()
                .addArgument("perl " + this.getWorkflowBaseDir() + "/scripts/gnos_upload_data.pl")
                .addArgument("--bam " + directorySNVCallingResults + "/" + file)
                .addArgument("--key " + gnosKey)
                //.addArgument("--outdir " + outputPrefix + "/" + gnosUploadDir)
                .addArgument("--metadata-urls " + gnosInputMetadataURLs)
                .addArgument("--upload-url " + gnosUploadFileURL);
                //.addArgument("--bam-md5sum-file  /datastore/" + outputdir + "/" + pid + "/mpileup/" + file + ".md5 ");

        if (debugmode) {
            job.getCommand().addArgument("--test");
        }

        return (job);
    }

}
