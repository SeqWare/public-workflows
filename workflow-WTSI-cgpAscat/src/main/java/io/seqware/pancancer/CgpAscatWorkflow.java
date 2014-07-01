package io.seqware.pancancer;

import java.util.Map;
import java.util.ArrayList;
import java.util.logging.Level;
import java.util.logging.Logger;
import net.sourceforge.seqware.pipeline.workflowV2.AbstractWorkflowDataModel;
import net.sourceforge.seqware.pipeline.workflowV2.model.Job;
import net.sourceforge.seqware.pipeline.workflowV2.model.SqwFile;

/**
 * <p>For more information on developing workflows, see the documentation at
 * <a href="http://seqware.github.io/docs/6-pipeline/java-workflows/">SeqWare Java Workflows</a>.</p>
 *
 * Quick reference for the order of methods called:
 * 1. setupDirectory
 * 2. setupFiles
 * 3. setupWorkflow
 * 4. setupEnvironment
 * 5. buildWorkflow
 *
 * See the SeqWare API for
 * <a href="http://seqware.github.io/javadoc/stable/apidocs/net/sourceforge/seqware/pipeline/workflowV2/AbstractWorkflowDataModel.html#setupDirectory%28%29">AbstractWorkflowDataModel</a>
 * for more information.
 */
public class CgpAscatWorkflow extends AbstractWorkflowDataModel {

  private boolean manualOutput=false;
  private String catPath, echoPath;
  private String greeting ="";
  private static String OUTDIR = "outdir/";
  private static String LOGDIR = "logdir/";

  // MEMORY variables //
  private String memGnosDownload, memAlleleCount, memAscat;
  // reference variables
  private String species, assembly;
  // GNOS identifiers
  private String tumourAnalysisId, controlAnalysisId;
  // test files, instead of GNOS ids
  private String tumourBam, normalBam;
  // workflow specific variables
  private String snpLoci, snpPos, snpGc, gender, installBase;

  private void init() {
    try {
      //optional properties
      if (hasPropertyAndNotNull("manual_output")) {
        manualOutput = Boolean.valueOf(getProperty("manual_output"));
      }
      if (hasPropertyAndNotNull("greeting")) {
        greeting = getProperty("greeting");
      }
      //these two properties are essential to the workflow. If they are null or do not
      //exist in the INI, the workflow should exit.
      catPath = getProperty("cat");
      echoPath = getProperty("echo");
    } catch (Exception e) {
      e.printStackTrace();
      throw new RuntimeException(e);
    }
  }

  @Override
  public void setupDirectory() {
    //since setupDirectory is the first method run, we use it to initialize variables too.
    init();
    // creates a dir1 directory in the current working directory where the workflow runs
    this.addDirectory(OUTDIR);
    this.addDirectory(LOGDIR);
  }

  @Override
  public Map<String, SqwFile> setupFiles() {
    try {
      // pull in config based overides

      // MEMORY //
      memGnosDownload = getProperty("memGnosDownload");
      memAlleleCount = getProperty("memAlleleCount");
      memAscat = getProperty("memAscat");

      // REFERENCE INFO //
      species = getProperty("species");
      assembly = getProperty("assembly");

      // Specific to this workflow //
      snpLoci = getProperty("snpLoci");
      snpPos = getProperty("snpPos");
      snpGc = getProperty("snpGc");
      gender = getProperty("gender");

      // Which data to process //
      if(hasPropertyAndNotNull("tumourAnalysisId") && hasPropertyAndNotNull("controlAnalysisId")) {
        // used in preference to test files if set //
        tumourAnalysisId = getProperty("tumourAnalysisId");
        controlAnalysisId = getProperty("controlAnalysisId");
      }

      // test files
      if(tumourAnalysisId == null || tumourAnalysisId.equals("CHANGEME")) {
        tumourBam = getProperty("tumourBam");
      }
      if(controlAnalysisId == null || controlAnalysisId.equals("CHANGEME")) {
        normalBam = getProperty("normalBam");
      }

      //environment
      installBase = getProperty("installBase");


    } catch (Exception ex) {
      ex.printStackTrace();
      throw new RuntimeException(ex);
    }
    return this.getFiles();
  }

  @Override
  public void buildWorkflow() {
    // First we need the tumour and normal BAM files (+bai)
    // this can be done in parallel, based on tumour/control
    // correlate names on by number of parallel jobs neeeded.
    String samples[] = {"tumour", "control"};

    // somewhere to save the jobs that downstream will be dependent on
    Job[] alleleCountJobs = new Job[2];

    for(int i=0; i<2; i++) {
      /*
      // @TODO, when we have a decider in place
      String thisId = "";
      switch(i){
        case 0: thisId = tumourAnalysisId;
        case 1: thisId = controlAnalysisId;
      }

      Job gnosDownload = this.getWorkflow().createBashJob("GNOSDownload");
      gnosDownload.setMaxMemory(memGnosDownload);
      gnosDownload.getCommand()
                    .addArgument(this.getWorkflowBaseDir()+"/bin/download_gnos.pl") // ?? @TODO Is there a generic script for this???
                    .addArgument(thisId); // @TODO can't use Donor ID as a donor can have multiple tumours (but only one normal)
      // the file needs to end up in tumourBam/normalBam
      */
      
      Job alleleCountJob = this.cgpAscatBaseJob("alleleCount", "allele_count", i+1);
      alleleCountJob.setMaxMemory(memAlleleCount);
//      alleleCountJob.addParent(gnosDownload);

      alleleCountJobs[i] = alleleCountJob;
    }

    Job alleleCountJob = this.cgpAscatBaseJob("ascat", "ascat", 1);
    alleleCountJob.setMaxMemory(memAscat);
    alleleCountJob.addParent(alleleCountJobs[0]);
    alleleCountJob.addParent(alleleCountJobs[1]);

    // @TODO then we need to write back to GNOS

  }

  private Job cgpAscatBaseJob(String name, String process, int index) {
    Job thisJob = this.getWorkflow().createBashJob(name);
    thisJob.getCommand()
              .addArgument(this.getWorkflowBaseDir()+ "/bin/wrapper.sh")
              .addArgument(installBase)
              .addArgument(LOGDIR.concat(process).concat(".").concat(Integer.toString(index)).concat(".log"))
              .addArgument("ascat.pl")
              .addArgument("-p " + process)
              .addArgument("-i " + index)
//              .addArgument("-as " + assembly) // will propably be reinstated when VCF added
//              .addArgument("-sp " + species)
              .addArgument("-o " + OUTDIR) // @TODO
              .addArgument("-t " + tumourBam) // @TODO with corresponding bai and bas files
              .addArgument("-n " + normalBam) // @TODO with corresponding bai and bas files
              .addArgument("-s " + snpLoci)
              .addArgument("-sp " + snpPos)
              .addArgument("-sg " + snpGc)
              ;
    if(gender.equals("L")) {
      thisJob.getCommand().addArgument("-l Y:2654896-2655740");
    }
    thisJob.getCommand().addArgument("-g " + gender);
    
    return thisJob;
  }

}
