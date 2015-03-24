package io.seqware;

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

    public static final String SHARED_WORKSPACE = "shared_workspace";
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
    private static final String EMBL_PREFIX = "EMBL.";
    private String controlBam = null;
    private String controlAnalysisId = null;
    private boolean localFileMode = false;
    
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

            this.vmInstanceType = getProperty("vmInstanceType");
            this.vmInstanceCores = getProperty("vmInstanceCores");
            this.vmInstanceMemGb = getProperty("vmInstanceMemGb");
            this.vmLocationCode = getProperty("vmLocationCode");
            if (this.hasPropertyAndNotNull("study-refname-override")) { this.studyRefnameOverride = getProperty("study-refname-override"); }
            if (this.hasPropertyAndNotNull("analysis-center-override")) { this.analysisCenterOverride = getProperty("analysis-center-override"); }
            
            // shared data directory
            commonDataDir = getProperty("common_data_dir");
            
            // DKFZ bundle info 
            dkfzDataBundleServer = getProperty("dkfzDataBundleServer");
            dkfzDataBundleUUID = getProperty("dkfzDataBundleUUID");
            dkfzDataBundleFile = getProperty("dkfzDataBundleFile");

            // record the date
            DateFormat dateFormat = new SimpleDateFormat("yyyyMMdd");
            Calendar cal = Calendar.getInstance();
            this.formattedDate = dateFormat.format(cal.getTime());
            
            // local file mode
            if(hasPropertyAndNotNull("localFileMode")) {
              localFileMode=Boolean.valueOf(getProperty("localFileMode"));
            }
            if (localFileMode) {
              System.err.println("WARNING\n\tRunning in direct file mode, direct access BAM files will be used and assumed to be full paths, change 'localFileMode' in ini file to disable\n");
            }
    
        } catch (Exception e) {
            throw new RuntimeException("Could not read property from ini", e);
        }
    }

    @Override
    /**
     * Note that this assumes that the ini file that was used to schedule is also mounted at /workflow.ini
     * This is pretty ugly
     */
    public void buildWorkflow() {

        // create a shared directory in /datastore on the host in order to download reference data
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

        // create reference EMBL data by calling download_data (currently a stub in the Perl version)
        Job getReferenceDataJob = this.getWorkflow().createBashJob("getEMBLDataFiles");
        getReferenceDataJob.getCommand().addArgument("cd " + commonDataDir + "/embl \n");
        getReferenceDataJob.getCommand().addArgument("if [ ! -f genome.fa ]; then wget http://s3.amazonaws.com/pan-cancer-data/pan-cancer-reference/genome.fa.gz \n gunzip genome.fa.gz || true \n fi \n");
        // upload this to S3 after testing
        getReferenceDataJob.getCommand().addArgument(
                "if [ ! -f hs37d5_1000GP.gc ]; then wget https://s3.amazonaws.com/pan-cancer-data/pan-cancer-reference/hs37d5_1000GP.gc \n fi \n");
        getReferenceDataJob.addParent(createSharedWorkSpaceJob);
        
        // download DKFZ data from GNOS
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
                                    + dkfzDataBundleFile + " --retries 10 --sleep-min 1 --timeout-min 60 && "
                                    + "cd " + dkfzDataBundleUUID + " && "
                                    + "tar zxf " + dkfzDataBundleFile + "' \n fi \n ");
        getDKFZReferenceDataJob.addParent(getReferenceDataJob);
        
        // create inputs
        Job previousJobPointer = getReferenceDataJob;
        for (int i = 0; i < analysisIds.size(); i++) {
            Job downloadJob = this.getWorkflow().createBashJob("download" + i);
            
            if (localFileMode) {
              // using hard links so it spans multiple exported filesystems to Docker
              downloadJob.getCommand()
              .addArgument("mkdir -p `pwd`/"+SHARED_WORKSPACE+"/inputs/" + analysisIds.get(i) + " && sudo ln "+bams.get(i)+" `pwd`/"+SHARED_WORKSPACE+"/inputs/"+analysisIds.get(i)+"/ && sudo ln "+bams.get(i)+".bai `pwd`/"+SHARED_WORKSPACE+"/inputs/"+analysisIds.get(i)+"/");
            } else {
              downloadJob
                      .getCommand()
                      .addArgument(
                              "docker run "
                                      // link in the input directory
                                      + "-v `pwd`/"
                                      + SHARED_WORKSPACE
                                      + "/inputs:/workflow_data "
                                      // link in the pem kee
                                      + "-v "
                                      + pemFile
                                      + ":/root/gnos_icgc_keyfile.pem seqware/pancancer_upload_download"
                                      // here is the Bash command to be run
                                      + " /bin/bash -c 'cd /workflow_data/ && perl -I /opt/gt-download-upload-wrapper/gt-download-upload-wrapper-1.0.3/lib "
                                      + "/opt/vcf-uploader/vcf-uploader-1.0.0/gnos_download_file.pl "
                                      // here is the command that is fed to gtdownload
                                      + "--command \"gtdownload -c /root/gnos_icgc_keyfile.pem -k 60 -vv " + gnosServer
                                      + "/cghub/data/analysis/download/" + analysisIds.get(i) + "\" --file " + analysisIds.get(i) + "/"
                                      + bams.get(i) + " --retries 10 --sleep-min 1 --timeout-min 60' \n");
            }
            downloadJob.addParent(previousJobPointer);
            // for now, make these sequential
            previousJobPointer = downloadJob;
        }

        // call the EMBL workflow
        previousJobPointer = runEMBLWorkflow(previousJobPointer);
        
        // call the DKFZ workflow
        previousJobPointer = runDKFZWorkflow(previousJobPointer);

        // cleanup
        // TODO: turn on cleanup
        Job cleanup = this.getWorkflow().createBashJob("cleanup");
        cleanup.getCommand().addArgument("#rf -Rf " + SHARED_WORKSPACE + " \n");
        cleanup.addParent(previousJobPointer);
    }

    /**
     *
     * @param previousJobPointer
     * @return a pointer to the last job created
     */
    private Job runEMBLWorkflow(Job previousJobPointer) {
        // call the EMBL workflow
        Job emblJob = this.getWorkflow().createBashJob("embl workflow");
        // we have to use a nested container here because of the seqware_lock
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

        for (String emblType : emblTypes) {
            for (String tumorAliquotId : tumorAliquotIds) {
              
              for (String varType : new String[]{"somatic", "germline"}) {

              // TODO: this isn't following the naming convention
              // should be "f393bb07-270c-2c93-e040-11ac0d484533.embl-delly-prefilter_1-0-0.20150311.somatic.sv.vcf.gz"
              // String baseFile = "`pwd`/" + SHARED_WORKSPACE + "/" + tumorAliquotId + ".embl-delly-prefilter_1-0-0."
              //          + this.formattedDate + ".somatic." + emblType;
                //String baseFile = "`pwd`/" + SHARED_WORKSPACE + "/" + tumorAliquotId + ".embl-delly_1-0-0-preFilter."+formattedDate+"."+varType;
                String baseFile = "/workflow_data/" + tumorAliquotId + ".embl-delly_1-0-0-preFilter."+formattedDate+"."+varType;

                vcfs.add(baseFile + ".vcf.gz");
                vcfmd5s.add(baseFile + ".vcf.gz.md5");
                tbis.add(baseFile + ".vcf.gz.tbi");
                tbimd5s.add(baseFile + ".vcf.gz.tbi.md5");
                
                tars.add(baseFile + ".readname.txt.tar.gz");
                tarmd5s.add(baseFile + ".readname.txt.tar.gz.md5");      
                
                tars.add(baseFile + "bedpe.txt.tar.gz");
                tarmd5s.add(baseFile + "bedpe.txt.tar.gz.md5");
                
                // need to upload cov.plots*
              }
            }
        }

        // FIXME: hardcoded versions, URLs, etc
        Job uploadJob = this.getWorkflow().createBashJob("uploadEMBL");
        StringBuffer overrideTxt = new StringBuffer();
        if (this.studyRefnameOverride != null) {
          overrideTxt.append(" --study-refname-override " + this.studyRefnameOverride);
        }
        if (this.analysisCenterOverride != null) {
          overrideTxt.append(" --analysis-center-override " + this.analysisCenterOverride);
        }
        uploadJob.getCommand().addArgument(
                "docker run "
                // link in the input directory
                        + "-v `pwd`/"
                        + SHARED_WORKSPACE
                        + ":/workflow_data "
                        // link in the pem kee
                        + "-v "
                        + pemFile
                        + ":/root/gnos_icgc_keyfile.pem "
                        // looked like a placeholder in the Perl script
                        // + "-v <embl_output_per_donor>:/result_data "
                        + "seqware/pancancer_upload_download "
                        // the command invoked on the container follows
                        + "/bin/bash -c 'cd /workflow_data && echo '{}' > /tmp/empty.json && mkdir -p uploads && dmesg "
                        // FIXME: testing, remove the skip
                        + "# perl -I /opt/gt-download-upload-wrapper/gt-download-upload-wrapper-1.0.3/lib "
                        + "/opt/vcf-uploader/vcf-uploader-1.0.0/gnos_upload_vcf.pl "
                        // parameters to gnos_upload
                        + "--metadata-urls "
                        + this.metadataURLs
                        + " --vcfs " + Joiner.on(',').join(vcfs) + " --vcf-md5sum-files " + Joiner.on(',').join(vcfmd5s) + " --vcf-idxs "
                        + Joiner.on(',').join(tbis) + " --vcf-idx-md5sum-files " + Joiner.on(',').join(tbimd5s) + " --tarballs "
                        + Joiner.on(',').join(tars) + " --tarball-md5sum-files " + Joiner.on(',').join(tarmd5s) + " --outdir uploads" 
                        + " --key /root/gnos_icgc_keyfile.pem --upload-url " + uploadServer
                        + " --qc-metrics-json /tmp/empty.json" + " --timing-metrics-json /tmp/empty.json"
                        + " --workflow-src-url https://bitbucket.org/weischen/pcawg-delly-workflow" + "--workflow-url https://registry.hub.docker.com/u/pancancer/pcawg-delly-workflow" + " --workflow-name EmblPancancerStr "
                        + " --workflow-version 1.0.0" + " --seqware-version " + this.getSeqware_version() + " --vm-instance-type "
                        + this.vmInstanceType + " --vm-instance-cores " + this.vmInstanceCores + " --vm-instance-mem-gb "
                        + this.vmInstanceMemGb + " --vm-location-code " + this.vmLocationCode + overrideTxt
                        // FIXME: testing, remove the skip
                        + " --skip-upload --skip-validate "
                        );
        uploadJob.addParent(previousJobPointer);
        // for now, make these sequential
        return uploadJob;
    }


    private Job runDKFZWorkflow(Job previousJobPointer) {
      
        // generate the tumor array
        ArrayList<String> tumorBams = new ArrayList<String>();
        for  (int i=0; i<tumorAnalysisIds.size(); i++) {
          if (localFileMode) {
            String[] tokens = bams.get(i).split("/");
            String bamFile = tokens[tokens.length - 1];
            tumorBams.add("/mnt/datastore/workflow_data/inputdata/"+tumorAnalysisIds.get(i)+"/"+bamFile);
          } else {
            tumorBams.add("/mnt/datastore/workflow_data/inputdata/"+tumorAnalysisIds.get(i)+"/"+bams.get(i));            
          }
        }
        
        // generate control bam
        String controlBamStr = "/mnt/datastore/workflow_data/inputdata/"+controlAnalysisId+"/"+controlBam;
        if (localFileMode) {
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
                        + "dkfz_dockered_workflows /bin/bash -c '/root/bin/runwrapper.sh' ");
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

          // TODO: this isn't following the naming convention
          // should be "f393bb07-270c-2c93-e040-11ac0d484533.embl-delly-prefilter_1-0-0.20150311.somatic.sv.vcf.gz"
          // String baseFile = "`pwd`/" + SHARED_WORKSPACE + "/" + tumorAliquotId + ".embl-delly-prefilter_1-0-0."
          //          + this.formattedDate + ".somatic." + emblType;
            //String baseFile = "`pwd`/" + SHARED_WORKSPACE + "/results/" + tumorAliquotId + ".dkfz-";
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

        // FIXME: hardcoded versions, URLs, etc
        Job uploadJob = this.getWorkflow().createBashJob("uploadEMBL");
        StringBuffer overrideTxt = new StringBuffer();
        if (this.studyRefnameOverride != null) {
          overrideTxt.append(" --study-refname-override " + this.studyRefnameOverride);
        }
        if (this.analysisCenterOverride != null) {
          overrideTxt.append(" --analysis-center-override " + this.analysisCenterOverride);
        }
        uploadJob.getCommand().addArgument(
                "docker run "
                // link in the input directory
                        + "-v `pwd`/"
                        + SHARED_WORKSPACE
                        + "/results:/workflow_data "
                        // link in the pem kee
                        + "-v "
                        + pemFile
                        + ":/root/gnos_icgc_keyfile.pem "
                        // looked like a placeholder in the Perl script
                        // + "-v <embl_output_per_donor>:/result_data "
                        + "seqware/pancancer_upload_download "
                        // the command invoked on the container follows
                        + "/bin/bash -c 'cd /workflow_data && echo '{}' > /tmp/empty.json && mkdir -p uploads && dmesg "
                        // FIXME: testing, remove the skip
                        + "# perl -I /opt/gt-download-upload-wrapper/gt-download-upload-wrapper-1.0.3/lib "
                        + "/opt/vcf-uploader/vcf-uploader-1.0.0/gnos_upload_vcf.pl "
                        // parameters to gnos_upload
                        + "--metadata-urls "
                        + this.metadataURLs
                        + " --vcfs " + Joiner.on(',').join(vcfs) + " --vcf-md5sum-files " + Joiner.on(',').join(vcfmd5s) + " --vcf-idxs "
                        + Joiner.on(',').join(tbis) + " --vcf-idx-md5sum-files " + Joiner.on(',').join(tbimd5s) + " --tarballs "
                        + Joiner.on(',').join(tars) + " --tarball-md5sum-files " + Joiner.on(',').join(tarmd5s) + " --outdir uploads" 
                        + " --key /root/gnos_icgc_keyfile.pem --upload-url " + uploadServer
                        + " --qc-metrics-json /tmp/empty.json" + " --timing-metrics-json /tmp/empty.json"
                        + " --workflow-src-url https://github.com/SeqWare/docker/tree/develop/dkfz_dockered_workflows" + "--workflow-url https://github.com/SeqWare/docker/tree/develop/dkfz_dockered_workflows" + " --workflow-name DkfzPancancerCnIndelSnv "
                        + " --workflow-version 1.0.0" + " --seqware-version " + this.getSeqware_version() + " --vm-instance-type "
                        + this.vmInstanceType + " --vm-instance-cores " + this.vmInstanceCores + " --vm-instance-mem-gb "
                        + this.vmInstanceMemGb + " --vm-location-code " + this.vmLocationCode + overrideTxt
                        // FIXME: testing, remove the skip
                        + " --skip-upload --skip-validate "
        );
        uploadJob.addParent(runWorkflow);
        // for now, make these sequential
        return uploadJob;
    }
}
