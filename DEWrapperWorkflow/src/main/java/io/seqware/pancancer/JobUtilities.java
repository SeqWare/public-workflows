/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */

package io.seqware.pancancer;

import com.google.common.base.Joiner;
import java.util.ArrayList;
import java.util.List;
import net.sourceforge.seqware.pipeline.workflowV2.model.Job;

/**
 * FIXME: the version number for the upload code is hard-coded below!!!
 *
 * @author boconnor
 */
public class JobUtilities {
    
  public Job gnosDownloadJob(Job thisJob, String outputDir, String pemFile, int timeout, int retries, String gnosServer, String analysisId, String bam, String dockerName) {

    thisJob.getCommand()
        .addArgument(
            "docker run "
                // link in the input directory
                + "-v "+outputDir+":/workflow_data "
                // link in the pem kee
                + "-v "
                + pemFile
                + ":/root/gnos_icgc_keyfile.pem "+dockerName+" "
                // here is the Bash command to be run
                + " /bin/bash -c 'cd /workflow_data/ && perl -I /opt/gt-download-upload-wrapper/gt-download-upload-wrapper-2.0.10/lib "
                + "/opt/vcf-uploader/vcf-uploader-2.0.4/gnos_download_file.pl "
                + "--url "+gnosServer+"/cghub/data/analysis/download/"+analysisId+" "
                + "--pem /root/gnos_icgc_keyfile.pem --file " + analysisId + "/"
                + bam + " --retries "+retries+" --timeout-min "+timeout+"' \n");
    
    return thisJob;
  }
  
  public Job s3DownloadJob(Job thisJob, String analysisId, String bamFile, String s3Url, String S3DownloadKey, String S3DownloadSecretKey) {
    
    thisJob.getCommand()
      .addArgument("mkdir -p "+analysisId+"; \n")
      .addArgument("mkdir -p ~/.aws/; \n")
      .addArgument("echo '[default]\n" +
        "aws_access_key_id = "+S3DownloadKey+"\n" +
        "aws_secret_access_key = "+S3DownloadSecretKey+"' > ~/.aws/config; \n")
      .addArgument("aws s3 cp " + s3Url + " " + analysisId + "/" + bamFile + " && ")
      .addArgument("aws s3 cp " + s3Url + ".bai " + analysisId + "/" + bamFile + ".bai ");

    return thisJob;
  }

  public Job localDownloadJob(Job thisJob, String outputDir, String bamFile) {

    thisJob.getCommand()
        .addArgument("mkdir -p " + outputDir + " && sudo ln "+bamFile+" "+outputDir+"/ && sudo ln "+bamFile+".bai "+outputDir+"/");

    return thisJob;
  }
  
  
  public Job localUploadJob(Job uploadJob, String workflowDataDir, String pemFile, String metadataURLs,
          List<String> vcfs, List<String> vcfmd5s, List<String> tbis, List<String> tbimd5s,
          List<String> tars, List<String> tarmd5s, String uploadServer, String seqwareVersion,
          String vmInstanceType, String vmLocationCode, String overrideTxt, String uploadLocalPath, String temp,
          int timeout, int retries, String qcJson, String timingJson, String workflowSrcUrl,
          String workflowUrl, String workflowName, String workflowVersion, String dockerName) {
    
    StringBuffer sb = new StringBuffer(overrideTxt);
    sb.append(" --upload-archive "+temp+" --skip-upload --skip-validate ");
    
    uploadJob = vcfUpload(uploadJob, workflowDataDir, pemFile, metadataURLs,
          vcfs, vcfmd5s, tbis, tbimd5s, tars, tarmd5s, uploadServer, seqwareVersion,
          vmInstanceType, vmLocationCode, sb.toString(), timeout, retries, qcJson, timingJson,
          workflowSrcUrl, workflowUrl, workflowName, workflowVersion, dockerName);
    
    uploadJob.getCommand().addArgument(" && rsync -rauv "+temp+"/*.tar.gz "+uploadLocalPath+"/");
    
    return(uploadJob);
    
  }
  
  public Job gnosUploadJob(Job uploadJob, String workflowDataDir, String pemFile, String metadataURLs,
          List<String> vcfs, List<String> vcfmd5s, List<String> tbis, List<String> tbimd5s,
          List<String> tars, List<String> tarmd5s, String uploadServer, String seqwareVersion,
          String vmInstanceType, String vmLocationCode, String overrideTxt, int timeout, int retries,
          String qcJson, String timingJson, String workflowSrcUrl,
          String workflowUrl, String workflowName, String workflowVersion, String dockerName) {
    
    return(vcfUpload(uploadJob, workflowDataDir, pemFile, metadataURLs,
          vcfs, vcfmd5s, tbis, tbimd5s, tars, tarmd5s, uploadServer, seqwareVersion,
          vmInstanceType, vmLocationCode, overrideTxt, timeout, retries, qcJson, timingJson,
          workflowSrcUrl, workflowUrl, workflowName, workflowVersion, dockerName));
    
  }
  
  /**
   *  FIXME: need to know the archive filename
   */
  public Job s3UploadJob(Job uploadJob, String workflowDataDir, String pemFile, String metadataURLs,
          List<String> vcfs, List<String> vcfmd5s, List<String> tbis, List<String> tbimd5s,
          List<String> tars, List<String> tarmd5s, String uploadServer, String seqwareVersion,
          String vmInstanceType, String vmLocationCode, String overrideTxt, String temp,
          String S3UploadArchiveKey, String S3UploadArchiveSecretKey, String uploadS3Bucket,
          int timeout, int retries, String qcJson, String timingJson, String workflowSrcUrl,
          String workflowUrl, String workflowName, String workflowVersion, String dockerName) {

      StringBuffer sb = new StringBuffer(overrideTxt);
      sb.append(" --upload-archive "+temp+" --skip-upload --skip-validate ");
    
      uploadJob = vcfUpload(uploadJob, workflowDataDir, pemFile, metadataURLs,
          vcfs, vcfmd5s, tbis, tbimd5s, tars, tarmd5s, uploadServer, seqwareVersion,
          vmInstanceType, vmLocationCode, sb.toString(), timeout, retries, qcJson, timingJson,
          workflowSrcUrl, workflowUrl, workflowName, workflowVersion, dockerName);
    
      uploadJob.getCommand()
        .addArgument(" && mkdir -p ~/.aws/; ")
        .addArgument("echo '[default]\n" +
          "aws_access_key_id = "+S3UploadArchiveKey+"\n" +
          "aws_secret_access_key = "+S3UploadArchiveSecretKey+"' > ~/.aws/config; ")
        .addArgument("aws s3 cp `readlink -f " + temp + "/*.tar.gz` " + uploadS3Bucket + "/;");
      
      return(uploadJob);
  }
  
  /**
   * TODO: need to include the JSON timing/qc files, remove the hard-coded URLs
   */
  public Job vcfUpload(Job uploadJob, String workflowDataDir, String pemFile, String metadataURLs,
          List<String> vcfs, List<String> vcfmd5s, List<String> tbis, List<String> tbimd5s,
          List<String> tars, List<String> tarmd5s, String uploadServer, String seqwareVersion,
          String vmInstanceType, String vmLocationCode, String overrideTxt, int timeout, int retries,
          String qcJson, String timingJson, String workflowSrcUrl, String workflowUrl,
          String workflowName, String workflowVersion, String dockerName) {
    
    uploadJob.getCommand().addArgument(
                "docker run "
                // link in the input directory
                        + "-v " + workflowDataDir
                        + ":/workflow_data "
                        // link in the pem kee
                        + "-v "
                        + pemFile
                        + ":/root/gnos_icgc_keyfile.pem "
                        + dockerName + " "
                        // the command invoked on the container follows
                        + "/bin/bash -c 'cd /workflow_data && mkdir -p uploads && "
                        + "perl -I /opt/gt-download-upload-wrapper/gt-download-upload-wrapper-2.0.10/lib "
                        + "/opt/vcf-uploader/vcf-uploader-2.0.4/gnos_upload_vcf.pl "
                        // parameters to gnos_upload
                        + "--metadata-urls "
                        + metadataURLs
                        + " --vcfs " + Joiner.on(',').join(vcfs) + " --vcf-md5sum-files " + Joiner.on(',').join(vcfmd5s) + " --vcf-idxs "
                        + Joiner.on(',').join(tbis) + " --vcf-idx-md5sum-files " + Joiner.on(',').join(tbimd5s) + " --tarballs "
                        + Joiner.on(',').join(tars) + " --tarball-md5sum-files " + Joiner.on(',').join(tarmd5s) + " --outdir uploads" 
                        + " --key /root/gnos_icgc_keyfile.pem --upload-url " + uploadServer
                        + " --qc-metrics-json " + qcJson
                        + " --timing-metrics-json " + timingJson
                        + " --workflow-src-url " + workflowSrcUrl
                        + " --workflow-url " + workflowUrl
                        + " --workflow-name "+workflowName
                        + " --timeout-min "+timeout+" --retries "+retries+" "
                        + " --workflow-version " + workflowVersion + " --seqware-version " + seqwareVersion + " --vm-instance-type "
                        + vmInstanceType + " --vm-instance-cores `nproc` --vm-instance-mem-gb "
                        + "`free | grep \"Mem:\" | awk \"{print \\\\$2 / 1000000 }\"` "
                        + " --vm-location-code " + vmLocationCode + overrideTxt + "' "
                        );
    
    return(uploadJob);
  }
  
}
