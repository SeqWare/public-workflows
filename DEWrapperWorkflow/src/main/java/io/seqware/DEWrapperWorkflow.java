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
    private String studyRefnameOverride;
    private String analysisCenterOverride;
    private String formattedDate;
    private String commonDataDir = "";
    private String dkfzDataBundleServer = "";
    private String dkfzDataBundleUUID = "";
    private String dkfzDataBundleFile = "";
    
    @Override
    public void setupWorkflow() {
        try {
            // these variables are for download of inputs
            String controlAnalysisId = getProperty("controlAnalysisId");
            this.analysisIds = Lists.newArrayList(getProperty("tumourAnalysisIds").split(","));
            analysisIds.add(controlAnalysisId);
            this.bams = Lists.newArrayList(getProperty("tumourBams").split(","));
            bams.add(getProperty("controlBam"));
            this.gnosServer = getProperty("gnosServer");
            this.pemFile = getProperty("pemFile");

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
            this.studyRefnameOverride = getProperty("study-refname-override");
            this.analysisCenterOverride = getProperty("analysis-center-override");
            
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

        // before this workflow is created, the q2seqware component will read the workflow.ini "order" and launch this workflow
        // NOTE: we should disable cron as well (crontab -r) since these containers will only exist for the purpose of running this
        // workflow

        // create a shared directory in /datastore on the host in order to download reference data
        Job createSharedWorkSpaceJob = this.getWorkflow().createBashJob("create_dirs");
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + " \n");
        // setup directories from Perl script
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/settings \n");
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/results \n");
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/working \n");
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/downloads/dkfz \n");
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/downloads/embl \n");
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/inputs \n");
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/uploads \n");
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + SHARED_WORKSPACE + "/data \n"); //deprecated, using data dirs below
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + commonDataDir + "/dkfz \n");
        createSharedWorkSpaceJob.getCommand().addArgument("mkdir -m 0777 -p " + commonDataDir + "/embl \n");

        // create reference EMBL data by calling download_data (currently a stub in the Perl version)
        Job getReferenceDataJob = this.getWorkflow().createBashJob("getEMBLDataFiles");
        getReferenceDataJob.getCommand().addArgument("cd " + commonDataDir + "/embl \n");
        getReferenceDataJob.getCommand().addArgument("if [ ! -f genome.fa ]; then wget http://s3.amazonaws.com/pan-cancer-data/pan-cancer-reference/genome.fa.gz \n fi \n");
        // this file has some garbage in it, so we cannot rely on the return code
        getReferenceDataJob.getCommand().addArgument("gunzip genome.fa.gz || true \n");
        // upload this to S3 after testing
        getReferenceDataJob.getCommand().addArgument(
                "if [ ! -f hs37d5_1000GP.gc ]; then wget https://s3.amazonaws.com/pan-cancer-data/pan-cancer-reference/hs37d5_1000GP.gc \n fi \n");
        getReferenceDataJob.addParent(createSharedWorkSpaceJob);
        
        // download DKFZ data from GNOS
        Job getDKFZReferenceDataJob = this.getWorkflow().createBashJob("getDKFZDataFiles");
        getDKFZReferenceDataJob.getCommand().addArgument("cd " + commonDataDir + "/dkfz \n");
        getDKFZReferenceDataJob.getCommand().addArgument("docker run "
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
                                    + dkfzDataBundleFile + " --retries 10 --sleep-min 1 --timeout-min 60' \n "
                                    + "cd " + dkfzDataBundleUUID + " \n "
                                    + "tar zxf " + dkfzDataBundleFile + " \n ");
        getDKFZReferenceDataJob.addParent(getReferenceDataJob);
        
        // create inputs
        Job previousJobPointer = getReferenceDataJob;
        for (int i = 0; i < analysisIds.size(); i++) {
            Job downloadJob = this.getWorkflow().createBashJob("download" + i);
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
            downloadJob.addParent(previousJobPointer);
            // for now, make these sequential
            previousJobPointer = downloadJob;
        }

        // call the EMBL workflow
        previousJobPointer = createEMBLJobs(previousJobPointer);
        
        // call the DKFZ workflow
        previousJobPointer = createDKFZWorkflow(previousJobPointer);

        // cleanup
        Job cleanup = this.getWorkflow().createBashJob("cleanup");
        cleanup.getCommand().addArgument("#rf -Rf " + SHARED_WORKSPACE + " \n");
        cleanup.addParent(previousJobPointer);
    }

    /**
     *
     * @param previousJobPointer
     * @return a pointer to the last job created
     */
    private Job createEMBLJobs(Job previousJobPointer) {
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

        emblJob.getCommand()
                .addArgument(
                // this is the actual command we run inside the container, which is to launch a workflow
                        "docker run --rm -h master -v `pwd`/" + SHARED_WORKSPACE + ":/datastore "
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
        String[] emblTypes = { "snv_mnv", "indel", "sv", "cnv" };

        List<String> vcfs = new ArrayList<>();
        List<String> tbis = new ArrayList<>();
        List<String> tars = new ArrayList<>();
        List<String> vcfmd5s = new ArrayList<>();
        List<String> tbimd5s = new ArrayList<>();
        List<String> tarmd5s = new ArrayList<>();

        for (String emblType : emblTypes) {
            for (String tumorAliquotId : tumorAliquotIds) {

                String baseFile = "`pwd`/" + SHARED_WORKSPACE + "/workflow_data/results/" + tumorAliquotId + ".embl_1-0-0."
                        + this.formattedDate + ".somatic." + emblType;

                vcfs.add(baseFile + ".vcf.gz");
                tbis.add(baseFile + ".vcf.gz.tbi");
                tars.add(baseFile + ".tar.gz");
                vcfmd5s.add(baseFile + ".vcf.gz.md5");
                tbimd5s.add(baseFile + ".vcf.gz.tbi.md5");
                tarmd5s.add(baseFile + ".tar.gz.md5");
            }
        }

        Job uploadJob = this.getWorkflow().createBashJob("uploadEMBL");
        uploadJob.getCommand().addArgument(
                "docker run "
                // link in the input directory
                        + "-v `pwd`/"
                        + SHARED_WORKSPACE
                        + "/workflow_data:/workflow_data "
                        // link in the pem kee
                        + "-v "
                        + pemFile
                        + ":/root/gnos_icgc_keyfile.pem "
                        // looked like a placeholder in the Perl script
                        // + "-v <embl_output_per_donor>:/result_data "
                        //
                        + "seqware/pancancer_upload_download "
                        + " dmesg "
                        // the command invoked on the container follows
                        + "#/bin/bash -c 'cd /workflow_data/results/ && "
                        + "perl -I /opt/gt-download-upload-wrapper/gt-download-upload-wrapper-1.0.3/lib "
                        + "/opt/vcf-uploader/vcf-uploader-1.0.0/gnos_upload_vcf.pl "
                        // parameters to gnos_upload
                        + "--metadata-urls "
                        + this.metadataURLs
                        //
                        + " --vcfs " + Joiner.on(',').join(vcfs) + " --vcf-md5sum-files " + Joiner.on(',').join(vcfmd5s) + " --vcf-idxs "
                        + Joiner.on(',').join(tbis) + " --vcf-idx-md5sum-files " + Joiner.on(',').join(tbimd5s) + " --tarballs "
                        + Joiner.on(',').join(tars) + " --tarball-md5sum-files " + Joiner.on(',').join(tarmd5s) + " --outdir `pwd`/"
                        + SHARED_WORKSPACE + "/uploads" + " --key " + uploadPemFile + " --upload-url " + uploadServer
                        + " --qc-metrics-json /tmp/empty.json" + " --timing-metrics-json /tmp/empty.json"
                        + " --workflow-src-url http://github.com" + "--workflow-url http://github.com" + " --workflow-name EMBL"
                        + " --workflow-version 1.0.0" + " --seqware-version " + this.getSeqware_version() + " --vm-instance-type "
                        + this.vmInstanceType + " --vm-instance-cores " + this.vmInstanceCores + " --vm-instance-mem-gb "
                        + this.vmInstanceMemGb + " --vm-location-code " + this.vmLocationCode + " --study-refname-override "
                        + this.studyRefnameOverride + " --analysis-center-override " + this.analysisCenterOverride + '\'');
        uploadJob.addParent(previousJobPointer);
        // for now, make these sequential
        return uploadJob;
    }

    private static final String EMBL_PREFIX = "EMBL.";

    private Job createDKFZWorkflow(Job previousJobPointer) {
      
      // the dellyFile is of the format: 
      
        Job generateIni = this.getWorkflow().createBashJob("generateDKFZ_ini");
        generateIni.getCommand().addArgument(
                "echo \"#!/bin/bash\n" + "tumorBams=( <full_path>/7723a85b59ebce340fe43fc1df504b35.bam )\n"
                        + "controlBam=8f957ddae66343269cb9b854c02eee2f.bam\n" + "dellyFiles=( <per_tumor> )\n" + "runACEeq=true\n"
                        + "runSNVCalling=true\n" + "runIndelCalling=true\n" + "date=" + this.formattedDate + "\" > " + SHARED_WORKSPACE
                        + "/settings/dkfz.ini \n");
        generateIni.addParent(previousJobPointer);
        // cleanup
        Job runWorkflow = this.getWorkflow().createBashJob("runDKFZ");
        runWorkflow.getCommand().addArgument(
                "docker run "
                        // mount shared directories
                        + "-v `pwd`/" + SHARED_WORKSPACE
                        + "/downloads/dkfz/bundledFiles:/mnt/datastore/bundledFiles "
                        // this path does not look right
                        + "-v `pwd`/" + SHARED_WORKSPACE + ":/mnt/datastore/workflow_data " + "-v `pwd`/" + SHARED_WORKSPACE
                        + "/settings/dkfz.ini:/mnt/datastore/workflow_data/workflow.ini " + "-v `pwd`/" + SHARED_WORKSPACE
                        + "/results:/mnt/datastore/result_data "
                        // the DKFZ image and the command we feed into it follow
                        + "dkfz_dockered_workflows /bin/bash -c '/root/bin/runwrapper.sh' ");
        runWorkflow.addParent(generateIni);
        // upload
        Job uploadWorkflow = this.getWorkflow().createBashJob("uploadDKFZ");
        uploadWorkflow.getCommand().addArgument(
                "docker run -v `pwd`/" + SHARED_WORKSPACE + "/workflow_data:/workflow_data " + "-v " + uploadPemFile
                        + ":/root/gnos_icgc_keyfile.pem "
                        // uncomment this when we get the real paths
                        // + "-v <dkfz_output_per_donor>:/result_data
                        // this is the container we're using
                        + "seqware/pancancer_upload_download "
                        // this is the placeholder command
                        + "dmesg\n"
                        // the real command follows
                        + "#bin/bash -c 'cd /result_data/ && run_upload.pl ... '\");\n");
        uploadWorkflow.addParent(runWorkflow);
        return uploadWorkflow;
    }
}
