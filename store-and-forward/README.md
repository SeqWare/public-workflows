# store-and-forward workflow

This is me messing around with modifying the existing DEWrapper to
create GNOS -> S3 downloader script.

Very simple workflow that takes an analysisID, and downloads:
  XML for that analysisID
  bam file for that analysisID
  bam.bai file for that analysisID
  
Then, will take the downloaded files and push them into an S3 bucket:
  foldername - analysisID, which will contain the a bam, a bai and an XML file.
