# 1.1.x (Future Release)

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
* DKFZ is missing timing JSON file

# 1.0.0

* Initial release
* Do not schedule 1.0.0 with multiple-tumor donors!!  1.1.x will support this

