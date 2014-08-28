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
public class CgpPindel extends AbstractWorkflowDataModel {

  private boolean manualOutput=false;
  private String catPath, echoPath;
  private String greeting ="";
  
  // Job defaults, don't forget to add to setupFiles if possible to overide via ini file.
  String memGnosDownload = "500";
  String memInputParse = "3000";
  String memPindel = "8000";
  String memPinVcf = "200";
  String memPinMerge = "1500";
  int threadsInput = 2;
  String refExclude = "NC_007605,hs37d5,GL%";
  String referenceFa, species, assembly, tumourAnalysisId, controlAnalysisId;

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
    this.addDirectory("dir1");
  }

  @Override
  public Map<String, SqwFile> setupFiles() {
    try {
      // register an plaintext input file using the information from the INI
      // provisioning this file to the working directory will be the first step in the workflow
      SqwFile file0 = this.createFile("file_in_0");
      file0.setSourcePath(getProperty("input_file"));
      file0.setType("text/plain");
      file0.setIsInput(true);
      
      // pull in config based overides
      
      // things to error on if not present in ini file
      ArrayList<String> reqIni = new ArrayList<String>();
      reqIni.add("input_reference");
      reqIni.add("species");
      reqIni.add("assembly");
      reqIni.add("tumourAnalysisId");
      reqIni.add("controlAnalysisId");
      for(int i=0; i<reqIni.size(); i++){
        String currPropName = reqIni.get(i);
        if(getProperty(currPropName) == null) {
          throw new RuntimeException("Unable to find '" + currPropName + "' in configuration file.");
        }
      }
      
      // MEMORY (there should be internal defaults for these //
      memGnosDownload = getProperty("memGnosDownload") == null ? memGnosDownload : getProperty("memGnosDownload");
      memInputParse = getProperty("memInputParse") == null ? memInputParse : getProperty("memInputParse");
      memPindel = getProperty("memPindel") == null ? memPindel : getProperty("memPindel");
      memPinVcf = getProperty("memPinVcf") == null ? memPinVcf : getProperty("memPinVcf");
      memPinMerge = getProperty("memPinMerge") == null ? memPinMerge : getProperty("memPinMerge");
      
      // THREADS (there should be internal defaults for these) //
      threadsInput = getProperty("threadsInput") == null ? threadsInput : Integer.parseInt(getProperty("threadsInput"));
      
      // REFERENCE INFO //
      referenceFa = getProperty("input_reference");
      species = getProperty("species");
      assembly = getProperty("assembly");
      tumourAnalysisId = getProperty("tumourAnalysisId");
      controlAnalysisId = getProperty("controlAnalysisId");
      

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
      
      Job inputParse = this.pindelBaseJob("pindelInput", "input", i+1, "SOMEOUTPUT_FOLDER", "TUMOUR_BAM", "CONTROL_BAM");
      inputParse.getCommand().addArgument("-c " + threadsInput);
      inputParse.setMaxMemory(memInputParse);
      inputParse.setThreads(threadsInput);
      inputParse.addParent(gnosDownload);
      
      parseJobs[i] = inputParse;
    }
    
    // determine number of refs to process
    // we know that this is static for PanCancer so be lazy 25 jobs (1-22,X,Y,MT)
    // but pindel needs to know the exclude list so hard code this
    Job pinVcfJobs[] = new Job[25];
    for(int i=0; i<25; i++) {
      Job pindelJob = this.pindelBaseJob("pindelPindel", "pindel", i+1, "SOMEOUTPUT_FOLDER", "TUMOUR_BAM", "CONTROL_BAM");
      pindelJob.setMaxMemory(memPindel);
      pindelJob.addParent(parseJobs[0]);
      pindelJob.addParent(parseJobs[1]);
      
      Job pinVcfJob = this.pindelBaseJob("pindelVcf", "pin2vcf", i+1, "SOMEOUTPUT_FOLDER", "TUMOUR_BAM", "CONTROL_BAM");
      pinVcfJob.setMaxMemory(memPinVcf);
      pinVcfJob.addParent(pindelJob);
      
      // making assumption that as pinVcf depends on pindelJob then only need to 
      // add dependency on the pinVcf
      pinVcfJobs[i] = pinVcfJob;
    }
    
    Job mergeJob = this.pindelBaseJob("pindelMerge", "merge", 1, "SOMEOUTPUT_FOLDER", "TUMOUR_BAM", "CONTROL_BAM");
    mergeJob.setMaxMemory(memPinMerge);
    for(int i=0; i<pinVcfJobs.length; i++) {
      mergeJob.addParent(pinVcfJobs[i]);
    }
    
    // @TODO then we need to write back to GNOS
    
  }

  private Job pindelBaseJob(String name, String process, int index, String outfolder, String tumBam, String ctrlBam) {
    Job thisJob = this.getWorkflow().createBashJob(name);
    thisJob.getCommand()
              .addArgument("-p " + process)
              .addArgument("-i " + index)
              .addArgument("-r " + referenceFa)
              .addArgument("-e " + refExclude)
              .addArgument("-as " + assembly)
              .addArgument("-sp " + species)
              .addArgument("-o " + outfolder) // @TODO
              .addArgument("-t " + tumBam) // @TODO with corresponding bai and bas files
              .addArgument("-n " + ctrlBam) // @TODO with corresponding bai and bas files
              ;
    return thisJob;
  }

}
