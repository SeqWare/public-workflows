1) Add a new validation step after GNOS download, to cross-reference XML to downloaded file contents<br>
2) Add Encryption to S3 Upload<br>
3) Add MD5 checking on upload to S3<br> 
4) leverage timeout, to create a fail/retry mechanism for S3 uploads (incase of a stuck upload scenario)
