# 1.0.1 (Future Release)

## TODO

* I think both the Delly and DKFZ docker containers will need to be revised to deal with multiple tumors
* create an uber-workflow
      * incorporate the Sanger and Broad workflows so all four run together
      * start with BWA workflow
      * will want to have a way to select which workflow to run, for the DKFZ workflow it will need to download Delly results if they are already submitted to GNOS
* on first run, the workflow pulls reference files from S3 and GNOS, we need a better alternative so that we don't eventually refer to broken links which would decrease the longevity of the workflow
* artifact for shared workflow modules that we can use for Sanger, DKFZ, EMBL, and maybe BWA workflows... specifically modules for upload download
* include bootstrap code to auto-provision work from central decider or /workflow.ini depending on ENV-Vars
* need to switch to --uuid for uploader so I know the output archive file name
* I may want to rethink the upload options so that you can upload to both S3 and GNOS at the same time, for example
* DKFZ is missing timing JSON file, I co-opted this for my full-workflow timing metrics but we really should get them to supply this and just add to it.  Also EMBL timing metrics need a total wall-time.

# 1.0.0

* Initial release
* Do not schedule 1.0.0 with multiple-tumor donors!!  1.0.1 will support this

## TODO

* true local file mode for Romina (to include XML files from GNOS)
* print some helpful messages before the workflow runs indicating where the output will be, touch files for completion, what modes have been set, etc
* continuing to have problems with DKFZ QC parsing... problem is it needs to be single-line... need to add this to the vcf uploader