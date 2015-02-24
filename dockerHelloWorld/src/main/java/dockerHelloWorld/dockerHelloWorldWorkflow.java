package dockerHelloWorld;

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
 * <a href="http://seqware.github.io/javadoc/stable/apidocs/net/sourceforge/seqware/pipeline/workflowV2/AbstractWorkflowDataModel.html#setupDirectory%28%29">AbstractWorkflowDataModel</a> 
 * for more information.
 */
public class dockerHelloWorldWorkflow extends AbstractWorkflowDataModel {

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

        // a simple bash job to call mkdir
	// note that this job uses the system's mkdir (which depends on the system being *nix)
        Job mkdirJob = this.getWorkflow().createBashJob("bash_mkdir");
        mkdirJob.getCommand().addArgument("mkdir test1");       
        
        // the following commands demo docker functionality
        
        // a simple job that demonstrates how to run a command inside a docker container
        // this particular container is downloaded from a central repository
	// the output is saved to the metadata database
        Job dockerJob1 = this.getWorkflow().createBashJob("dockerJob1");
	dockerJob1.getCommand().addArgument("docker run --rm centos dmesg").addArgument(" | ").addArgument("tee dir1/tree");
        dockerJob1.addParent(mkdirJob);
	dockerJob1.addFile(createOutputFile("dir1/tree", "txt/plain", manualOutput));       
        
        // a simple job that demonstrates how to load a container from within the SeqWare bundle (in case you have a proprietary container image)
        Job dockerJob2 = this.getWorkflow().createBashJob("dockerJob2");
        
        dockerJob2.getCommand().addArgument("docker load -i " + this.getWorkflowBaseDir() + "/workflows/postgres_image.tar");
        dockerJob2.getCommand().addArgument("\n");
	dockerJob2.getCommand().addArgument("docker run --rm eg_postgresql ps aux | grep postgres").addArgument(" | ").addArgument("tee dir1/ps_out");
        dockerJob2.addParent(mkdirJob);
	dockerJob2.addFile(createOutputFile("dir1/ps_out", "txt/plain", manualOutput));       
        
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
