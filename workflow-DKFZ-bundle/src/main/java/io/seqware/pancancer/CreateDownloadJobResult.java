package io.seqware.pancancer;
	
import java.io.*;
import net.sourceforge.seqware.pipeline.workflowV2.*;
import net.sourceforge.seqware.pipeline.workflowV2.model.*;

class CreateDownloadJobResult {
	public final Job job;
	public final String elementID;
	public File outputDirectory;
	
	public CreateDownloadJobResult(Job job, String elementID, File outputDirectory) {
		this.job = job;
		this.elementID = elementID;
		this.outputDirectory = outputDirectory;
	}
}
