# store-and-forward workflow

Very simple workflow that takes an analysisID, and downloads:<br>
  - XML for that analysisID<br>
  - bam file for that analysisID<br>
  - bam.bai file for that analysisID<br><br>
  
Then, will take the downloaded files and push them into an S3 bucket:<br>
  - foldername - analysisID<br>
      -- bam file<br>
      -- bai file<br>
      -- xml file<br>
