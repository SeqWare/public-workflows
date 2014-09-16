package com.github.seqware;

import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;
import net.sourceforge.seqware.pipeline.workflowV2.AbstractWorkflowDataModel;
import net.sourceforge.seqware.pipeline.workflowV2.model.Job;
import net.sourceforge.seqware.pipeline.workflowV2.model.SqwFile;

public class WorkflowClient extends AbstractWorkflowDataModel {
  
  // some helpful paths used in various steps, notice these are all just
  // files that have been bundled into the "bin" directory.  Also note
  // that java is different here, it was pulled into the bin directory 
  // as a result of a pom.xml dependency.
  String java = this.getWorkflowBaseDir()+"/bin/jre1.6.0_29/bin/java";
  String picardSort = this.getWorkflowBaseDir()+"/bin/picard-tools-1.92/SortSam.jar";
  String picardFixmate = this.getWorkflowBaseDir()+"/bin/picard-tools-1.92/FixMateInformation.jar";
  String samtools = this.getWorkflowBaseDir()+"/bin/samtools-0.1.19/samtools";
  String picardReorder = this.getWorkflowBaseDir()+"/bin/picard-tools-1.92/ReorderSam.jar";
  String gatk = this.getWorkflowBaseDir()+"/bin/GenomeAnalysisTK.jar";
  String tmpDir = "tmpDir";

  @Override
  public Map<String, SqwFile> setupFiles() {

    try {

      // provision the input BAM
      SqwFile inFile0 = this.createFile("input_bam_file");
      inFile0.setSourcePath(this.getProperty("input_bam_file"));
      inFile0.setIsInput(true);

      // register an output file, in this case the VCF GATK calls
      // see http://seqware.github.io/docs/6-pipeline/file-types for setType() conventions
      SqwFile outFile1 = this.createFile("output_vcf_file");
      outFile1.setSourcePath("output.vcf");
      outFile1.setType("text/vcf-4");
      outFile1.setIsOutput(true);
      outFile1.setForceCopy(true);
      // if output_file is set in the ini then use it to set the destination of this file
      // rather than output_prefix + output_dir + filename which is the default
      if (hasPropertyAndNotNull("output_file")) {
        outFile1.setOutputPath(getProperty("output_file"));
      }

      // to comply with the API return the map
      return this.getFiles();

    } catch (Exception ex) {
      Logger.getLogger(WorkflowClient.class.getName()).log(Level.SEVERE, null, ex);
      return (null);
    }
  }

  @Override
  public void setupDirectory() {
    // creates a "working" directory in the current working directory where the workflow runs
    // we use this for a temp dir for the various tools used in this workflow
    this.addDirectory("tmpDir");
  }

  @Override
  public void buildWorkflow() {

    try {

      // get various properties from the INI file
      String samtoolsFlag = null, fasta = null, dbsnpVcf = null;
      Integer picardSortMem = null, picardFixmateMem = null, samtoolsMem = null;
      Integer gatkUnifiedGenotyperMem = null, picardReorderMem = null, threads = null;
      try {
        samtoolsFlag = getProperty("samtools_flag");
        fasta = getProperty("fasta");
        dbsnpVcf = getProperty("dbsnp_vcf");
        samtoolsMem = Integer.parseInt(getProperty("samtools_slots_memory_gigabytes"));
        picardSortMem = Integer.parseInt(getProperty("picard_sort_mem"));
        picardFixmateMem = Integer.parseInt(getProperty("picard_fixmate_mem"));
        gatkUnifiedGenotyperMem = Integer.parseInt(getProperty("gatk_unified_genotyper_mem"));
        picardReorderMem = Integer.parseInt(getProperty("picard_reorder_mem"));
        threads = Integer.parseInt(getProperty("threads"));
      } catch (Exception e) {
        e.printStackTrace();
      }

      // setup various file paths
      String inputFilepath = this.getFiles().get("input_bam_file").getProvisionedPath();
      String filteredReads = inputFilepath + ".filtered.bam";
      String sortedReads = inputFilepath + ".filtered.namesorted.bam";
      String fixmateReads = inputFilepath + ".filtered.namesorted.fixmate.bam";
      String reorderedReads = inputFilepath + ".filtered.namesorted.fixmate.reorder.bam";
      String outputFilepath = this.getFiles().get("output_vcf_file").getProvisionedPath();

      // quality filter
      Job id1 = samtoolsFilterReads(samtools, samtoolsMem, samtoolsFlag, inputFilepath, filteredReads);
      // sort the file in readname order to fixmate
      Job id2 = picardSort(java, picardSortMem, picardSort, filteredReads, sortedReads);
      id2.addParent(id1);
      // fixmate
      Job id3 = picardFixMate(java, picardFixmateMem, picardFixmate, sortedReads, fixmateReads);
      id3.addParent(id2);
      // reorder so GATK won't crash
      Job id4 = gatkReorder(java, picardReorderMem, picardReorder, fixmateReads, reorderedReads, fasta);
      id4.addParent(id3);
      // now do the actual variant calling to produce a VCF file
      Job id5 = gatkUnifiedGenotyper(java, gatkUnifiedGenotyperMem, gatk, fasta, dbsnpVcf, threads, reorderedReads, outputFilepath);
      id5.addParent(id4);

    } catch (Exception ex) {
      Logger.getLogger(WorkflowClient.class.getName()).log(Level.SEVERE, null, ex);
    }

  }
  
    private Job gatkUnifiedGenotyper(String java, int gatkUnifiedGenotyperMem, String gatk, String refFasta, String dbsnpVcf,
          int threads, String inputFilepath, String outputFilepath) {
    // creating a job
    Job job42 = this.getWorkflow().createBashJob("gatk_genotype");
    job42.getCommand().addArgument(java + " -Xmx" + gatkUnifiedGenotyperMem + "g -Djava.io.tmpdir=" + tmpDir);
    job42.getCommand().addArgument("-jar " + gatk);
    job42.getCommand().addArgument("-T UnifiedGenotyper");
    job42.getCommand().addArgument("-R " + refFasta + " -D " + dbsnpVcf);
    job42.getCommand().addArgument("-I " + inputFilepath);
    job42.getCommand().addArgument("-o " + outputFilepath);
    job42.getCommand().addArgument("-nt "+threads);
    job42.getCommand().addArgument("-glm BOTH -S SILENT -U ALL -filterMBQ  -A AlleleBalance -A BaseCounts -A AlleleBalanceBySample -A DepthPerAlleleBySample -A MappingQualityZeroBySample --max_alternate_alleles 2 --max_deletion_fraction 2 --min_base_quality_score 5 -minIndelCnt 5 -dcov 2000");
    // setting the memory requirements
    job42.setMaxMemory(gatkUnifiedGenotyperMem + "000");
    return job42;
    
  }

  private Job gatkReorder(String java, int picardReorderMem, String picardReorder, String fixmateReads, String reorderedReads, String fasta) {
    // create job
    Job job = this.getWorkflow().createBashJob("picard_reorder");
    job.getCommand().addArgument(java + " -Xmx" + picardReorderMem + "g -jar " + picardReorder);
    job.getCommand().addArgument("INPUT=" + fixmateReads + " OUTPUT=" + reorderedReads);
    job.getCommand().addArgument("VALIDATION_STRINGENCY=SILENT TMP_DIR=" + tmpDir + "CREATE_INDEX=true");
    job.getCommand().addArgument("REFERENCE=" + fasta);
    // set memory
    job.setMaxMemory(picardReorderMem + "000");
    return (job);
  }

  private Job picardFixMate(String java, int picardFixmateMem, String picardFixmate, String inputFilepath, String outputFilepath) {
    Job job02 = this.getWorkflow().createBashJob("PicardFixMate");
    job02.getCommand().addArgument(java + " -Xmx" + picardFixmateMem + "g -jar " + picardFixmate);
    job02.getCommand().addArgument("INPUT=" + inputFilepath + " OUTPUT=" + outputFilepath);
    job02.getCommand().addArgument("VALIDATION_STRINGENCY=SILENT TMP_DIR=" + tmpDir + " SORT_ORDER=coordinate CREATE_INDEX=true");
    job02.setMaxMemory(picardFixmateMem + "000");
    return job02;
  }

  private Job picardSort(String java, int picardSortMem, String picardSort, String inputFilepath, String outputFilepath) {
    Job job01 = this.getWorkflow().createBashJob("PicardSortByQuery");
    job01.getCommand().addArgument(java + " -Xmx" + picardSortMem + "g -jar " + picardSort + " INPUT=" + inputFilepath);
    job01.getCommand().addArgument("OUTPUT=" + outputFilepath + " VALIDATION_STRINGENCY=SILENT SORT_ORDER=queryname TMP_DIR=" + tmpDir);
    job01.setMaxMemory(picardSortMem + "000");
    return job01;
  }

  private Job samtoolsFilterReads(String samtools, int samtoolsMem, String samtoolsFlag, String inputFile, String outputFile) {
    Job job00 = this.getWorkflow().createBashJob("SamtoolsFilterUnmappedMultihitReads");
    job00.getCommand().addArgument(samtools).addArgument("view -b -F").addArgument(samtoolsFlag);
    job00.getCommand().addArgument(inputFile).addArgument(" > " + outputFile);
    job00.setMaxMemory(samtoolsMem + "000");
    return job00;
  }

  private Job picardIndexBam(String java, int picardIndexBamMem, String picardIndex, String bamFilepath) {
    Job job41 = this.getWorkflow().createBashJob("PicardIndexBam");
    job41.getCommand().addArgument(java + " -Xmx" + picardIndexBamMem + "g -Djava.io.tmpdir=" + tmpDir);
    job41.getCommand().addArgument("-jar " + picardIndex + " VALIDATION_STRINGENCY=SILENT");
    job41.getCommand().addArgument("INPUT=" + bamFilepath);
    job41.getCommand().addArgument("TMP_DIR=" + tmpDir);
    job41.setMaxMemory(picardIndexBamMem + "000");
    return job41;
  }


}
