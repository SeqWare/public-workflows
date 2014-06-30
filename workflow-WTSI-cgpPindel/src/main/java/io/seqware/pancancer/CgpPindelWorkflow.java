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
public class CgpPindelWorkflow extends AbstractWorkflowDataModel {

  private boolean manualOutput=false;
  private String catPath, echoPath;
  private String greeting ="";
  private static String OUTDIR = "outdir/";
  private static String LOGDIR = "logdir/";
  
  // MEMORY variables //
  private String memGnosDownload, memInputParse, memPindel, memPinVcf, memPinMerge , memPinFlag;
  // reference variables
  private String refExclude, referenceFa, species, assembly;
  // values for processes that can be multi-threaded
  private int threadsInput;
  // GNOS identifiers
  private String tumourAnalysisId, controlAnalysisId;
  // test files, instead of GNOS ids
  private String tumourBam, normalBam;
  // workflow specific variables
  private String installBase, simpleRep, filters, softfilters, geneFootPrints, pindelNp;

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
      memInputParse = getProperty("memInputParse");
      memPindel = getProperty("memPindel");
      memPinVcf = getProperty("memPinVcf");
      memPinMerge = getProperty("memPinMerge");
      memPinFlag = getProperty("memPinFlag");
      
      // THREADS for processes that can have them set //
      threadsInput = Integer.valueOf(getProperty("threadsInput"));
      
      // REFERENCE INFO //
      referenceFa = getProperty("input_reference");
      species = getProperty("species");
      assembly = getProperty("assembly");
      
      // Specific to this workflow //
      simpleRep = getProperty("simpleRep");
      filters = getProperty("filters");
      softfilters = getProperty("softfilters");
      geneFootPrints = getProperty("geneFootPrints");
      pindelNp = getProperty("pindelNp");
      refExclude = getProperty("refExclude");
      
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
    Job parseJobs[] = new Job[2];

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
  
      Job inputParse = this.pindelBaseJob("pindelInput", "input", i+1);
      inputParse.getCommand().addArgument("-c " + threadsInput);
      inputParse.setMaxMemory(memInputParse);
      inputParse.setThreads(threadsInput);
//      inputParse.addParent(gnosDownload);
      
      parseJobs[i] = inputParse;
    }
    
    // determine number of refs to process
    // we know that this is static for PanCancer so be lazy 25 jobs (1-22,X,Y,MT)
    // but pindel needs to know the exclude list so hard code this
    Job pinVcfJobs[] = new Job[25];
    for(int i=0; i<25; i++) {
      Job pindelJob = this.pindelBaseJob("pindelPindel", "pindel", i+1);
      pindelJob.setMaxMemory(memPindel);
      pindelJob.addParent(parseJobs[0]);
      pindelJob.addParent(parseJobs[1]);
      
      Job pinVcfJob = this.pindelBaseJob("pindelVcf", "pin2vcf", i+1);
      pinVcfJob.setMaxMemory(memPinVcf);
      pinVcfJob.addParent(pindelJob);
      
      // pinVcf depends on pindelJob so only need have dependency on the pinVcf
      pinVcfJobs[i] = pinVcfJob;
    }
    
    Job mergeJob = this.pindelBaseJob("pindelMerge", "merge", 1);
    mergeJob.setMaxMemory(memPinMerge);
    for (Job pinVcfJob : pinVcfJobs) {
      mergeJob.addParent(pinVcfJob);
    }
    
    Job flagJob = this.pindelBaseJob("pindelFlag", "flag", 1);
    flagJob.setMaxMemory(memPinFlag);
    flagJob.addParent(mergeJob);
    
    // @TODO then we need to write back to GNOS
    
  }

  private Job pindelBaseJob(String name, String process, int index) {
    Job thisJob = this.getWorkflow().createBashJob(name);
    thisJob.getCommand()
              .addArgument(this.getWorkflowBaseDir()+ "/bin/wrapper.sh")
              .addArgument(installBase)
              .addArgument(LOGDIR.concat(process).concat(".").concat(Integer.toString(index)).concat(".log"))
              .addArgument("pindel.pl")
              .addArgument("-p " + process)
              .addArgument("-i " + index)
              .addArgument("-r " + referenceFa)
              .addArgument("-e " + refExclude)
              .addArgument("-as " + assembly)
              .addArgument("-sp " + species)
              .addArgument("-o " + OUTDIR) // @TODO
              .addArgument("-t " + tumourBam) // @TODO with corresponding bai and bas files
              .addArgument("-n " + normalBam) // @TODO with corresponding bai and bas files
              .addArgument("-s " + simpleRep)
              .addArgument("-f " + filters)
              .addArgument("-g " + geneFootPrints)
              .addArgument("-u " + pindelNp)
              .addArgument("-sf " + softfilters)
              ;
    return thisJob;
  }

}
