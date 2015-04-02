package io.seqware.pancancer;

import com.google.common.base.Joiner;
import com.google.common.collect.Lists;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.Map.Entry;
import net.sourceforge.seqware.pipeline.workflowV2.AbstractWorkflowDataModel;
import net.sourceforge.seqware.pipeline.workflowV2.model.Job;

/**
 * <p>
 * For more information on developing workflows, see the documentation at <a
 * href="http://seqware.github.io/docs/6-pipeline/java-workflows/">SeqWare Java Workflows</a>.
 * </p>
 *
 * Quick reference for the order of methods called: 1. setupDirectory 2. setupFiles 3. setupWorkflow 4. setupEnvironment 5. buildWorkflow
 *
 * See the SeqWare API for <a href=
 * "http://seqware.github.io/javadoc/stable/apidocs/net/sourceforge/seqware/pipeline/workflowV2/AbstractWorkflowDataModel.html#setupDirectory%28%29"
 * >AbstractWorkflowDataModel</a> for more information.
 */
public class DEWrapperWorkflow extends AbstractWorkflowDataModel {
  
    // job utilities
    private JobUtilities utils = new JobUtilities();

    // variables
    private static final String SHARED_WORKSPACE = "shared_workspace";
    private static final String EMBL_PREFIX = "EMBL.";
    private static final String DKFZ_PREFIX = "EMBL.";
    private ArrayList<String> analysisIds = null;
    private ArrayList<String> tumorAnalysisIds = null;
    private ArrayList<String> bams = null;
    private String gnosServer = null;
    private String pemFile = null;
    private String uploadPemFile = null;
    private String uploadServer = null;
    private String metadataURLs = null;
    private List<String> tumorAliquotIds = null;
    private String vmInstanceType;
    private String vmInstanceCores;
    private String vmInstanceMemGb;
    private String vmLocationCode;
    private String studyRefnameOverride = null;
    private String analysisCenterOverride = null;
    private String formattedDate;
    private String commonDataDir = "";
    private String dkfzDataBundleServer = "";
    private String dkfzDataBundleUUID = "";
    private String dkfzDataBundleFile = "";
    private String controlBam = null;
    private String controlAnalysisId = null;
    private String downloadSource = null;
    private String uploadDestination = null;
    // cleanup
    private Boolean cleanup = false;
    private Boolean cleanupBams = false;
    // GNOS timeout
    private int gnosTimeoutMin = 20;
    private int gnosRetries = 3;
    // S3
    private String controlS3URL = null;
    private ArrayList<String> tumourBamS3Urls = null;
    private ArrayList<String> allBamS3Urls = null;
    private String s3Key = null;
    private String s3SecretKey = null;
    private String uploadLocalPath = null;
    private String uploadS3BucketPath = null;
    // workflows to run
    private Boolean runEmbl = true;
    private Boolean runDkfz = true;
    
    @Override
    public void setupWorkflow() {
        try {
          
            // these variables are for download of inputs
            String controlAnalysisId = getProperty("controlAnalysisId");
            this.analysisIds = Lists.newArrayList(getProperty("tumourAnalysisIds").split(","));
            analysisIds.add(controlAnalysisId);
            this.tumorAnalysisIds = Lists.newArrayList(getProperty("tumourAnalysisIds").split(","));
            this.bams = Lists.newArrayList(getProperty("tumourBams").split(","));
            bams.add(getProperty("controlBam"));
            this.gnosServer = getProperty("gnosServer");
            this.pemFile = getProperty("pemFile");
            
            // S3 URLs
            controlS3URL = getProperty("controlBamS3Url");
            tumourBamS3Urls = Lists.newArrayList(getProperty("tumourBamS3Urls").split(","));
            allBamS3Urls = Lists.newArrayList(getProperty("tumourBamS3Urls").split(","));
            allBamS3Urls.add(controlS3URL);
            s3Key = getProperty("s3Key");
            s3SecretKey = getProperty("s3SecretKey");
            uploadS3BucketPath = getProperty("uploadS3BucketPath");
            
            // controls
            this.controlBam = getProperty("controlBam");
            this.controlAnalysisId = getProperty("controlAnalysisId");

            // these variables are those extra required for EMBL upload
            this.uploadServer = getProperty("uploadServer");
            this.uploadPemFile = getProperty("uploadPemFile");
            StringBuilder metadataURLBuilder = new StringBuilder();
            metadataURLBuilder.append(uploadServer).append("/cghub/metadata/analysisFull/").append(controlAnalysisId);
            for (String id : Lists.newArrayList(getProperty("tumourAnalysisIds").split(","))) {
                metadataURLBuilder.append(",").append(uploadServer).append("/cghub/metadata/analysisFull/").append(id);
            }
            this.metadataURLs = metadataURLBuilder.toString();
            this.tumorAliquotIds = Lists.newArrayList(getProperty("tumourAliquotIds").split(","));

            // background information on VMs
            // TODO: Cores and MemGb can be filled in at runtime
            this.vmInstanceType = getProperty("vmInstanceType");
            this.vmInstanceCores = getProperty("vmInstanceCores");
            this.vmInstanceMemGb = getProperty("vmInstanceMemGb");
            this.vmLocationCode = getProperty("vmLocationCode");
            
            // overrides for study name and analysis center
            if (this.hasPropertyAndNotNull("study-refname-override")) { this.studyRefnameOverride = getProperty("study-refname-override"); }
            if (this.hasPropertyAndNotNull("analysis-center-override")) { this.analysisCenterOverride = getProperty("analysis-center-override"); }
            
            // shared data directory
            commonDataDir = getProperty("common_data_dir");
            
            // DKFZ bundle info 
            dkfzDataBundleServer = getProperty("DKFZ.dkfzDataBundleServer");
            dkfzDataBundleUUID = getProperty("DKFZ.dkfzDataBundleUUID");
            dkfzDataBundleFile = getProperty("DKFZ.dkfzDataBundleFile");

            // record the date
            DateFormat dateFormat = new SimpleDateFormat("yyyyMMdd");
            Calendar cal = Calendar.getInstance();
            this.formattedDate = dateFormat.format(cal.getTime());
            
            // local file mode
            downloadSource = getProperty("downloadSource");
            uploadDestination = getProperty("uploadDestination");
            uploadLocalPath = getProperty("uploadLocalPath");
            if ("local".equals(downloadSource)) {
              System.err.println("WARNING\n\tRunning in direct file mode, direct access BAM files will be used and assumed to be full paths\n");
            } else if ("S3".equals(downloadSource)) {
              System.err.println("WARNING\n\tRunning in S3 file mode, direct access BAM files will be used and assumed to be full paths\n");
            }
            if ("local".equals(uploadDestination)) {
              System.err.println("WARNING\n\tRunning in local file upload mode, analyzed results files will be written to a local directory, you will need to upload to GNOS yourself\n");
            } else if ("S3".equals(uploadDestination)) {
              System.err.println("WARNING\n\tRunning in S3 upload mode, analyzed results files will be written to an S3 bucket, you will need to upload to GNOS yourself\n");
            }
            
            // timeout
            gnosTimeoutMin = Integer.parseInt(getProperty("gnosTimeoutMin"));
            gnosRetries = Integer.parseInt(getProperty("gnosRetries"));
            
            // cleanup
            if(hasPropertyAndNotNull("cleanup")) {
              cleanup=Boolean.valueOf(getProperty("cleanup"));
            }
            if(hasPropertyAndNotNull("cleanupBams")) {
              cleanupBams=Boolean.valueOf(getProperty("cleanupBams"));
            }
            
            // workflow options
            if(hasPropertyAndNotNull("runDkfz")) {
              runDkfz=Boolean.valueOf(getProperty("runDkfz"));
            }
            /* if(hasPropertyAndNotNull("runEmbl")) {
              runEmbl=Boolean.valueOf(getProperty("runEmbl"));
            } */
    
        } catch (Exception e) {
            throw new RuntimeException("Could not read property from ini", e);
        }
    }
    
    /*
     MAIN WORKFLOW METHOD
    */

    @Override
    /**
     * The core of the overall workflow
     */
    public void buildWorkflow() {

        // create a shared directory in /datastore on the host in order to download reference data
        Job createSharedWorkSpaceJob = createDirectoriesJob();
                
        // create reference EMBL data by calling download_data (currently a stub in the Perl version)
        Job getReferenceDataJob = createReferenceDataJob(createSharedWorkSpaceJob);
        
        // download DKFZ data from GNOS
        Job getDKFZReferenceDataJob = createDkfzReferenceDataJob(getReferenceDataJob);
        
        // create inputs
        Job lastDownloadDataJob = createDownloadDataJobs(getDKFZReferenceDataJob);

        // call the EMBL workflow
        Job emblJob = runEMBLWorkflow(lastDownloadDataJob);
        Job lastWorkflow = emblJob;
        
        if (runDkfz) {
          // call the DKFZ workflow
          Job dkfzJob = runDKFZWorkflow(emblJob);
          lastWorkflow = dkfzJob;
        }
        
        // now cleanup
        cleanupWorkflow(lastWorkflow);
        
    }
    
    
    
    
    /*
     JOB BUILDING METHODS
    */
    
    private void cleanupWorkflow(Job lastJob) {
        if (cleanup) {
          Job cleanup = this.getWorkflow().createBashJob("cleanup");
          cleanup.getCommand().addArgument("echo rf -Rf * \n");
          cleanup.addParent(lastJob);
        } else if (cleanupBams) {
          Job cleanup = this.getWorkflow().createBashJob("cleanupBams");
          cleanup.getCommand()
                  .addArgument("rm -f ./*/*.bam && ")
                  .addArgument("rm -f ./shared_workspace/*/*.bam; ");
          cleanup.addParent(lastJob);
        }
    }

    /**
     *
     * @param previousJobPointer
     * @return a pointer to the last job created
     */
    private Job runEMBLWorkflow(Job previousJobPointer) {
      
        // call the EMBL workflow
        Job emblJob = this.getWorkflow().createBashJob("embl_workflow");
        
        // make config
        boolean count = true;
        for (Entry<String, String> entry : this.getConfigs().entrySet()) {
            if (entry.getKey().startsWith(EMBL_PREFIX)) {
                String cat = ">>";
                if (count) { cat = ">"; count = false; }
                emblJob.getCommand().addArgument(
                // we need a better way of getting the ini file here, this may not be safe if the workflow has escaped key-values
                         "echo \"" + entry.getKey().replaceFirst(EMBL_PREFIX, "") + "\"=\"" + entry.getValue() + "\" "+cat+" `pwd`/"
                                + SHARED_WORKSPACE + "/settings/embl.ini \n"); 
            }
        }
        // now supply date
        emblJob.getCommand().addArgument("echo \"date="+formattedDate+"\" >> `pwd`/"+SHARED_WORKSPACE + "/settings/embl.ini \n");

        // the actual docker command
        emblJob.getCommand()
                .addArgument(
                // this is the actual command we run inside the container, which is to launch a workflow
                        "docker run --rm -h master -v `pwd`/" + SHARED_WORKSPACE + ":/datastore "
                                // data files
                                + "-v " + commonDataDir + "/embl:/datafiles "
                                // mount the workflow.ini
                                + "-v `pwd`/" + SHARED_WORKSPACE
                                + "/settings/embl.ini:/workflow.ini "
                                // the container
                                + "pancancer/pcawg-delly-workflow "
                                // command received by seqware (replace this with a real call to Delly after getting bam files downloaded)
                                + "/start.sh \"seqware bundle launch --dir /mnt/home/seqware/DELLY/target/Workflow_Bundle_DELLY_1.0-SNAPSHOT_SeqWare_1.1.0-alpha.6 --engine whitestar-parallel --no-metadata --ini /workflow.ini\" \n");
        // with a real workflow, we would pass in the workflow.ini

        emblJob.addParent(previousJobPointer);
        previousJobPointer = emblJob;

        // upload the EMBL results
        String[] emblTypes = { "sv" };

        List<String> vcfs = new ArrayList<>();
        List<String> tbis = new ArrayList<>();
        List<String> tars = new ArrayList<>();
        List<String> vcfmd5s = new ArrayList<>();
        List<String> tbimd5s = new ArrayList<>();
        List<String> tarmd5s = new ArrayList<>();

        // FIXME: these don't quite follow the naming convention
        for (String tumorAliquotId : tumorAliquotIds) {
        
          String baseFile = "/workflow_data/" + tumorAliquotId + ".embl-delly_1-0-0-preFilter."+formattedDate;

          vcfs.add(baseFile + ".germline.vcf.gz");
          vcfs.add(baseFile + ".sv.vcf.gz");
          vcfs.add(baseFile + ".somatic.sv.vcf.gz");
          
          vcfmd5s.add(baseFile + ".germline.vcf.gz.md5");
          vcfmd5s.add(baseFile + ".sv.vcf.gz.md5");
          vcfmd5s.add(baseFile + ".somatic.sv.vcf.gz.md5");
          
          tbis.add(baseFile + ".germline.vcf.gz.tbi");
          tbis.add(baseFile + ".sv.vcf.gz.tbi");
          tbis.add(baseFile + ".somatic.sv.vcf.gz.tbi");
          
          tbimd5s.add(baseFile + ".germline.vcf.gz.tbi.md5");
          tbimd5s.add(baseFile + ".sv.vcf.gz.tbi.md5");
          tbimd5s.add(baseFile + ".somatic.sv.vcf.gz.tbi.md5");

          tars.add(baseFile + ".germline.readname.txt.tar.gz");
          tarmd5s.add(baseFile + ".germline.readname.txt.tar.gz.md5");      

          tars.add(baseFile + ".germline.bedpe.txt.tar.gz");
          tarmd5s.add(baseFile + ".germline.bedpe.txt.tar.gz.md5");
          
          tars.add(baseFile + ".somatic.sv.readname.txt.tar.gz");
          tarmd5s.add(baseFile + ".somatic.sv.readname.txt.tar.gz.md5");      

          tars.add(baseFile + ".somatic.sv.bedpe.txt.tar.gz");
          tarmd5s.add(baseFile + ".somatic.sv.bedpe.txt.tar.gz.md5");
          
          tars.add(baseFile + ".cov.plots.tar.gz");
          tarmd5s.add(baseFile + ".cov.plots.tar.gz.md5");
          
          tars.add(baseFile + ".cov.tar.gz");
          tarmd5s.add(baseFile + ".cov.tar.gz.md5");

        }
        
        // perform upload to GNOS
        // FIXME: hardcoded versions, URLs, etc
        // FIXME: temp location problem, see "/tmp/" below
        Job uploadJob = this.getWorkflow().createBashJob("uploadEMBL");
        
        // params
        StringBuffer overrideTxt = new StringBuffer();
        if (this.studyRefnameOverride != null) {
          overrideTxt.append(" --study-refname-override " + this.studyRefnameOverride);
        }
        if (this.analysisCenterOverride != null) {
          overrideTxt.append(" --analysis-center-override " + this.analysisCenterOverride);
        }

        // Now do the upload based on the destination chosen
        if ("local".equals(uploadDestination)) {

          // using hard links so it spans multiple exported filesystems to Docker
          uploadJob = utils.localUploadJob(uploadJob, "`pwd`/"+SHARED_WORKSPACE, pemFile, metadataURLs,
          vcfs, vcfmd5s, tbis, tbimd5s, tars, tarmd5s, uploadServer, Version.SEQWARE_VERSION,
          vmInstanceType, vmLocationCode, overrideTxt.toString(), uploadLocalPath, "/tmp/",
          gnosTimeoutMin, gnosRetries);

        } else if ("GNOS".equals(uploadDestination)) {

          uploadJob = utils.gnosUploadJob(uploadJob, "`pwd`/"+SHARED_WORKSPACE, pemFile, metadataURLs,
          vcfs, vcfmd5s, tbis, tbimd5s, tars, tarmd5s, uploadServer, Version.SEQWARE_VERSION,
          vmInstanceType, vmLocationCode, overrideTxt.toString(),
          gnosTimeoutMin, gnosRetries);

        } else if ("S3".equals(uploadDestination)) {

          uploadJob = utils.s3UploadJob(uploadJob, "`pwd`/"+SHARED_WORKSPACE, pemFile, metadataURLs,
          vcfs, vcfmd5s, tbis, tbimd5s, tars, tarmd5s, uploadServer, Version.SEQWARE_VERSION,
          vmInstanceType, vmLocationCode, overrideTxt.toString(), "/tmp/", s3Key, s3SecretKey,
          uploadS3BucketPath, gnosTimeoutMin, gnosRetries);

        } else {
          throw new RuntimeException("Don't know what download Type "+downloadSource+" is!");
        }

        uploadJob.addParent(previousJobPointer);
        // for now, make these sequential
        return uploadJob;
        
    }


    private Job runDKFZWorkflow(Job previousJobPointer) {
      
        // generate the tumor array
        ArrayList<String> tumorBams = new ArrayList<String>();
        for  (int i=0; i<tumorAnalysisIds.size(); i++) {
          if ("local".equals(downloadSource)) {
            String[] tokens = bams.get(i).split("/");
            String bamFile = tokens[tokens.length - 1];
            tumorBams.add("/mnt/datastore/workflow_data/inputdata/"+tumorAnalysisIds.get(i)+"/"+bamFile);
          } else {
            tumorBams.add("/mnt/datastore/workflow_data/inputdata/"+tumorAnalysisIds.get(i)+"/"+bams.get(i));            
          }
        }
        
        // generate control bam
        String controlBamStr = "/mnt/datastore/workflow_data/inputdata/"+controlAnalysisId+"/"+controlBam;
        if ("local".equals(downloadSource)) {
          String[] tokens = controlBam.split("/");
          controlBam = tokens[tokens.length - 1];
        }
        
        // tumor delly files
        ArrayList<String> tumorDelly = new ArrayList<String>();
        for  (int i=0; i<tumorAliquotIds.size(); i++) {
          tumorDelly.add("/mnt/datastore/workflow_data/inputdata/"+tumorAliquotIds.get(i)+".embl-delly_1-0-0-preFilter."+formattedDate+".germline.bedpe.txt");
        }
      
        Job generateIni = this.getWorkflow().createBashJob("generateDKFZ_ini");
        generateIni.getCommand().addArgument(
                        "echo \"#!/bin/bash\n" 
                        + "tumorBams=( "+Joiner.on(" ").join(tumorBams)+" )\n"
                        + "aliquotIDs=( "+Joiner.on(" ").join(tumorAliquotIds)+" )\n"
                        + "controlBam=/mnt/datastore/workflow_data/inputdata/"+controlAnalysisId+"/"+controlBam+"\n" 
                        + "dellyFiles=( "+Joiner.on(" ").join(tumorDelly)+" )\n"
                        + "runACEeq=true\n"
                        + "runSNVCalling=true\n" 
                        + "runIndelCalling=true\n"
                        + "date=" + this.formattedDate
                        + "\" > " + SHARED_WORKSPACE
                        + "/settings/dkfz.ini \n");
        generateIni.addParent(previousJobPointer);
        
        // prepare file mount paths
        StringBuffer mounts = new StringBuffer();
        for (int i=0; i<tumorAliquotIds.size(); i++) {
          String aliquotId = tumorAliquotIds.get(i);
          String analysisId = tumorAnalysisIds.get(i);
          mounts.append(" -v `pwd`/" + SHARED_WORKSPACE + "/inputs/"+analysisId+":/mnt/datastore/workflow_data/inputdata/"+analysisId+" ");
          mounts.append(" -v `pwd`/" + SHARED_WORKSPACE + "/"+aliquotId+".embl-delly_1-0-0-preFilter."+formattedDate+".germline.bedpe.txt:/mnt/datastore/workflow_data/inputdata/"+aliquotId+".embl-delly_1-0-0-preFilter."+formattedDate+".germline.bedpe.txt ");
        }
        // now deal with the control
        mounts.append(" -v `pwd`/" + SHARED_WORKSPACE + "/inputs/"+controlAnalysisId+":/mnt/datastore/workflow_data/inputdata/"+controlAnalysisId+" ");
        
        // run the docker for DKFZ
        Job runWorkflow = this.getWorkflow().createBashJob("runDKFZ");
        runWorkflow.getCommand().addArgument(
                "docker run "
                        // mount shared directories
                        + "-v " + commonDataDir + "/dkfz/" + dkfzDataBundleUUID 
                        + "/bundledFiles:/mnt/datastore/bundledFiles "
                        // this path does not look right
                        + mounts
                        + "-v `pwd`/" + SHARED_WORKSPACE + "/testdata:/mnt/datastore/testdata "
                        + "-v `pwd`/" + SHARED_WORKSPACE
                        + "/settings/dkfz.ini:/mnt/datastore/workflow_data/workflow.ini "
                        + "-v `pwd`/" + SHARED_WORKSPACE
                        + "/results:/mnt/datastore/resultdata "
                        // the DKFZ image and the command we feed into it follow
                        + "pancancer/dkfz_dockered_workflows /bin/bash -c '/root/bin/runwrapper.sh' ");
        runWorkflow.addParent(generateIni);
        
        // upload the DKFZ results
        String[] emblTypes = { "sv" };

        List<String> vcfs = new ArrayList<>();
        List<String> tbis = new ArrayList<>();
        List<String> tars = new ArrayList<>();
        List<String> vcfmd5s = new ArrayList<>();
        List<String> tbimd5s = new ArrayList<>();
        List<String> tarmd5s = new ArrayList<>();


        for (String tumorAliquotId : tumorAliquotIds) {

            String baseFile = "/workflow_data/" + tumorAliquotId + ".dkfz-";

            // VCF
            vcfs.add(baseFile + "indelCalling_1-0-114."+formattedDate+".germline.indel.vcf.gz");
            vcfs.add(baseFile + "indelCalling_1-0-114."+formattedDate+".somatic.indel.vcf.gz");
            vcfs.add(baseFile + "snvCalling_1-0-114."+formattedDate+".germline.snv_mnv.vcf.gz");
            vcfs.add(baseFile + "snvCalling_1-0-114."+formattedDate+".somatic.snv_mnv.vcf.gz");
            vcfs.add(baseFile + "copyNumberEstimation_1-0-114."+formattedDate+".somatic.cnv.vcf.gz");
            
            // VCF MD5
            vcfmd5s.add(baseFile + "indelCalling_1-0-114."+formattedDate+".germline.indel.vcf.gz.md5");
            vcfmd5s.add(baseFile + "indelCalling_1-0-114."+formattedDate+".somatic.indel.vcf.gz.md5");
            vcfmd5s.add(baseFile + "snvCalling_1-0-114."+formattedDate+".germline.snv_mnv.vcf.gz.md5");
            vcfmd5s.add(baseFile + "snvCalling_1-0-114."+formattedDate+".somatic.snv_mnv.vcf.gz.md5");
            vcfmd5s.add(baseFile + "copyNumberEstimation_1-0-114."+formattedDate+".somatic.cnv.vcf.gz.md5");

            // Tabix
            tbis.add(baseFile + "indelCalling_1-0-114."+formattedDate+".somatic.germline.indel.vcf.gz.tbi");
            tbis.add(baseFile + "indelCalling_1-0-114."+formattedDate+".somatic.somatic.indel.vcf.gz.tbi");
            tbis.add(baseFile + "snvCalling_1-0-114."+formattedDate+".germline.snv_mnv.vcf.gz.tbi");
            tbis.add(baseFile + "snvCalling_1-0-114."+formattedDate+".somatic.snv_mnv.vcf.gz.tbi");
            tbis.add(baseFile + "copyNumberEstimation_1-0-114."+formattedDate+".somatic.cnv.vcf.gz.tbi");
            
            // Tabix MD5
            tbimd5s.add(baseFile + "indelCalling_1-0-114."+formattedDate+".somatic.germline.indel.vcf.gz.tbi.md5");
            tbimd5s.add(baseFile + "indelCalling_1-0-114."+formattedDate+".somatic.somatic.indel.vcf.gz.tbi.md5");
            tbimd5s.add(baseFile + "snvCalling_1-0-114."+formattedDate+".germline.snv_mnv.vcf.gz.tbi.md5");
            tbimd5s.add(baseFile + "snvCalling_1-0-114."+formattedDate+".somatic.snv_mnv.vcf.gz.tbi.md5");
            tbimd5s.add(baseFile + "copyNumberEstimation_1-0-114."+formattedDate+".somatic.cnv.vcf.gz.tbi.md5");

            // Tarballs LEFT OFF HERE
            tars.add(baseFile + "-copyNumberEstimation_1-0-114."+formattedDate+".somatic.cnv.tar.gz");
            tars.add(baseFile + "-indelCalling_1-0-114."+formattedDate+".somatic.indel.tar.gz");
            tars.add(baseFile + "-snvCalling_1-0-114."+formattedDate+".somatic.snv_mnv.tar.gz");
            
            // Tarballs MD5
            tarmd5s.add(baseFile + "-copyNumberEstimation_1-0-114."+formattedDate+".somatic.cnv.tar.gz.md5");
            tarmd5s.add(baseFile + "-indelCalling_1-0-114."+formattedDate+".somatic.indel.tar.gz.md5");
            tarmd5s.add(baseFile + "-snvCalling_1-0-114."+formattedDate+".somatic.snv_mnv.tar.gz.md5");

        }

        Job uploadJob = this.getWorkflow().createBashJob("uploadDKFZ");
        StringBuffer overrideTxt = new StringBuffer();
        if (this.studyRefnameOverride != null) {
          overrideTxt.append(" --study-refname-override " + this.studyRefnameOverride);
        }
        if (this.analysisCenterOverride != null) {
          overrideTxt.append(" --analysis-center-override " + this.analysisCenterOverride);
        }
        
        // Now do the upload based on the destination chosen
        if ("local".equals(uploadDestination)) {

          // using hard links so it spans multiple exported filesystems to Docker
          uploadJob = utils.localUploadJob(uploadJob, "`pwd`/"+SHARED_WORKSPACE, pemFile, metadataURLs,
          vcfs, vcfmd5s, tbis, tbimd5s, tars, tarmd5s, uploadServer, Version.SEQWARE_VERSION,
          vmInstanceType, vmLocationCode, overrideTxt.toString(), uploadLocalPath, "/tmp/",
          gnosTimeoutMin, gnosRetries);

        } else if ("GNOS".equals(uploadDestination)) {

          uploadJob = utils.gnosUploadJob(uploadJob, "`pwd`/"+SHARED_WORKSPACE, pemFile, metadataURLs,
          vcfs, vcfmd5s, tbis, tbimd5s, tars, tarmd5s, uploadServer, Version.SEQWARE_VERSION,
          vmInstanceType, vmLocationCode, overrideTxt.toString(),
          gnosTimeoutMin, gnosRetries);

        } else if ("S3".equals(uploadDestination)) {

          uploadJob = utils.s3UploadJob(uploadJob, "`pwd`/"+SHARED_WORKSPACE, pemFile, metadataURLs,
          vcfs, vcfmd5s, tbis, tbimd5s, tars, tarmd5s, uploadServer, Version.SEQWARE_VERSION,
          vmInstanceType, vmLocationCode, overrideTxt.toString(), "/tmp/", s3Key, s3SecretKey,
          uploadS3BucketPath, gnosTimeoutMin, gnosRetries);

        } else {
          throw new RuntimeException("Don't know what download Type "+downloadSource+" is!");
        }

        uploadJob.addParent(runWorkflow);
        
        return uploadJob;
    }

  private Job createDirectoriesJob() {
    Job createSharedWorkSpaceJob = this.getWorkflow().createBashJob("create_dirs");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + " \n");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/settings \n");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/results \n");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/working \n");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/downloads/dkfz \n");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/downloads/embl \n");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/inputs \n");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/testdata \n");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/uploads \n");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/data \n"); //deprecated, using data dirs below
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + commonDataDir + "/dkfz \n");
    createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + commonDataDir + "/embl \n");

    return(createSharedWorkSpaceJob);
  }

  private Job createReferenceDataJob(Job createSharedWorkSpaceJob) {
    
    Job getReferenceDataJob = this.getWorkflow().createBashJob("getEMBLDataFiles");
    getReferenceDataJob.getCommand().addArgument("cd " + commonDataDir + "/embl \n");
    getReferenceDataJob.getCommand().addArgument("if [ ! -f genome.fa ]; then wget http://s3.amazonaws.com/pan-cancer-data/pan-cancer-reference/genome.fa.gz \n gunzip genome.fa.gz || true \n fi \n");
    // upload this to S3 after testing
    getReferenceDataJob.getCommand().addArgument(
            "if [ ! -f hs37d5_1000GP.gc ]; then wget https://s3.amazonaws.com/pan-cancer-data/pan-cancer-reference/hs37d5_1000GP.gc \n fi \n");
    getReferenceDataJob.addParent(createSharedWorkSpaceJob);
    return(getReferenceDataJob);
    
  }

  private Job createDkfzReferenceDataJob(Job getReferenceDataJob) {
    Job getDKFZReferenceDataJob = this.getWorkflow().createBashJob("getDKFZDataFiles");
    getDKFZReferenceDataJob.getCommand().addArgument("cd " + commonDataDir + "/dkfz \n");
    getDKFZReferenceDataJob.getCommand().addArgument("if [ ! -d " + dkfzDataBundleUUID + "/bundledFiles ]; then docker run "
                                // link in the input directory
                                + "-v `pwd`:/workflow_data "
                                // link in the pem key
                                + "-v "
                                + pemFile
                                + ":/root/gnos_icgc_keyfile.pem seqware/pancancer_upload_download"
                                // here is the Bash command to be run
                                + " /bin/bash -c 'cd /workflow_data/ && perl -I /opt/gt-download-upload-wrapper/gt-download-upload-wrapper-1.0.3/lib "
                                + "/opt/vcf-uploader/vcf-uploader-1.0.0/gnos_download_file.pl "
                                // here is the command that is fed to gtdownload
                                + "--command \"gtdownload -c /root/gnos_icgc_keyfile.pem -k 60 -vv " + dkfzDataBundleServer
                                + "/cghub/data/analysis/download/" + dkfzDataBundleUUID + "\" --file " + dkfzDataBundleUUID + "/"
                                + dkfzDataBundleFile + " --retries "+gnosRetries+" --sleep-min 1 --timeout-min "+gnosTimeoutMin+" && "
                                + "cd " + dkfzDataBundleUUID + " && "
                                + "tar zxf " + dkfzDataBundleFile + "' \n fi \n ");
    getDKFZReferenceDataJob.addParent(getReferenceDataJob);
    return(getDKFZReferenceDataJob);
  }

  private Job createDownloadDataJobs(Job previousJob) {
    
    Job previousJobPointer = previousJob;
    
    for (int i = 0; i < analysisIds.size(); i++) {
      
      Job downloadJob = this.getWorkflow().createBashJob("download_" + i);
      
      if ("local".equals(downloadSource)) {
        
        // using hard links so it spans multiple exported filesystems to Docker
        downloadJob = utils.localDownloadJob(downloadJob, "`pwd`/"+SHARED_WORKSPACE+"/inputs/"+analysisIds.get(i), bams.get(i));
        
      } else if ("GNOS".equals(downloadSource)) {
        
        // GET FROM INI
        
        downloadJob = utils.gnosDownloadJob(downloadJob, "`pwd`/"+SHARED_WORKSPACE+"/inputs", pemFile, gnosTimeoutMin, gnosRetries, gnosServer, analysisIds.get(i), bams.get(i) );
        
      } else if ("S3".equals(downloadSource)) {
        
        downloadJob = utils.s3DownloadJob(downloadJob, analysisIds.get(i), bams.get(i), allBamS3Urls.get(i), s3Key, s3SecretKey);
        
      } else {
        throw new RuntimeException("Don't know what download Type "+downloadSource+" is!");
      }
      
      downloadJob.addParent(previousJobPointer);
      // for now, make these sequential
      previousJobPointer = downloadJob;
    }
    return(previousJobPointer);
  }

}
