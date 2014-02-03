package io.seqware.pancancer;

import java.util.Map;
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
 * for more information.
 */
public class DKFZSNVCallingWorkflow extends AbstractWorkflowDataModel {

    private boolean manualOutput=false;
    private String catPath, echoPath;
    private String greeting ="";

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
      
      } catch (Exception ex) {
        ex.printStackTrace();
	throw new RuntimeException(ex);
      }
      return this.getFiles();
    }
    
   
    @Override
    public void buildWorkflow() {
        try {
            // a simple bash job to call mkdir
            // note that this job uses the system's mkdir (which depends on the system being *nix)
            Job GNOSDownload = this.getWorkflow().createBashJob("GNOSDownload");
            GNOSDownload.getCommand().addArgument(this.getWorkflowBaseDir()+"/bin/download_gnos.pl "+getProperty("GNOSDonorID")+" [tumor|control]_{GNOSDonorID}_merged.bam.[rmdup|dupmarked].bam");
            
            // The directory: analysis/DKFZ/SNV/panCancer/{GNOSDonorID}/alignment/[tumor|control]_{GNOSDonorID}_merged.bam.[rmdup|dupmarked].bam
            
            Job SNVCalling = this.getWorkflow().createBashJob("SNVCalling");
            SNVCalling.addParent(GNOSDownload);
            SNVCalling.getCommand().addArgument(this.getWorkflowBaseDir()+"/lib/roddy/roddy.sh run config "+getProperty("GNOSDonorID"));
            
            // TODO: look at Kerien's code for generating GNOS metadata
            
            // The directory: analysis/DKFZ/SNV/panCancer/{GNOSDonorID}/mpileup[_indel]/[snvs|indels]_{GNOSDonorID}.vcf.gz
            Job GNOSUpload = this.getWorkflow().createBashJob("GNOSUpload");
            GNOSUpload.getCommand().addArgument(this.getWorkflowBaseDir()+"/bin/upload_gnos.pl "+getProperty("GNOSDonorID")+" analysis/DKFZ/SNV/panCancer/{GNOSDonorID}/mpileup[_indel]/[snvs|indels]_{GNOSDonorID}.vcf.gz");
            GNOSUpload.addParent(SNVCalling);
            
            //String inputFilePath = this.getFiles().get("file_in_0").getProvisionedPath();
            
            // a simple bash job to cat a file into a test file
            // the file is not saved to the metadata database
            /*Job copyJob1 = this.getWorkflow().createBashJob("bash_cp");
            copyJob1.setCommand(catPath + " " + inputFilePath + "> test1/test.out");
            copyJob1.addParent(mkdirJob);*/
            
            // a simple bash job to echo to an output file and concat an input file
            // the file IS saved to the metadata database
            /*Job copyJob2 = this.getWorkflow().createBashJob("bash_cp");
            copyJob2.getCommand().addArgument(echoPath).addArgument(greeting).addArgument(" > ").addArgument("dir1/output");
            copyJob2.getCommand().addArgument(";");
            copyJob2.getCommand().addArgument(catPath + " " +inputFilePath+ " >> dir1/output");
            copyJob2.addParent(mkdirJob);
            copyJob2.addFile(createOutputFile("dir1/output", "txt/plain", manualOutput));       */ 
        } catch (Exception ex) {
            Logger.getLogger(DKFZSNVCallingWorkflow.class.getName()).log(Level.SEVERE, null, ex);
        }

    }

    private SqwFile createOutputFile(String workingPath, String metatype, boolean manualOutput) {
    // register an output file
        SqwFile file1 = new SqwFile(); 
        file1.setSourcePath(workingPath);
        file1.setType(metatype);
        file1.setIsOutput(true);
        file1.setForceCopy(true);
	
        // if manual_output is set in the ini then use it to set the destination of this file
        if (manualOutput) { 
	    file1.setOutputPath(this.getMetadata_output_file_prefix() + getMetadata_output_dir() + "/" + workingPath);
	} else {
	    file1.setOutputPath(this.getMetadata_output_file_prefix() + getMetadata_output_dir() + "/" 
		+ this.getName() + "_" + this.getVersion() + "/" + this.getRandom() + "/" + workingPath);
	}
	return file1;
    }

}
