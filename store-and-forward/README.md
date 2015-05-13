# store-and-forward workflow

Very simple workflow that takes an analysisID, and downloads:<br>
  - Benchmark Sample Data<br>
  - Tumour Sample Data<br>
  - VCF Data<br>
  
Then, will take the downloaded files and push them into an S3 bucket:<br>
  - foldername - analysisID<br>
      -- All File Content<br>
      -- analysis.xml file containing GNOS metadata<br>
