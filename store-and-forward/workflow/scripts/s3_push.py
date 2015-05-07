import boto
import os
import sys

def main():
    path = sys.argv[1]
    bucket_name = sys.argv[2]
    aws_access_key = sys.argv[3]
    aws_secret_key = sys.argv[4]
    try:
        print "Connecting to S3 ... "
        conn = boto.connect_s3(aws_access_key, aws_secret_key)
        print "Connecting to Bucket: %s ... " % (bucket_name)
        bucket = conn.get_bucket(bucket_name)
        print "Beginning Upload of directory %s ... " % (path)
        for f in os.listdir(path):
            # Skip subdirectories, upload files only (for now)
            if os.path.isfile(os.path.join(path, f)):
                k = boto.s3.key.Key(bucket)
                k.name = f
                print "Uploading %s ... " % (f)
                k.set_contents_from_filename(os.path.join(path, f), replace=True)
                print "Upload complete!"
        conn.close()
    except:
        print "Error interfacing with S3."
        sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) == 1 or len(sys.argv) > 5:
        print "Usage:\n s3upload.py directory-to-upload bucketname s3key s3secretkey\n"
        sys.exit(1)
    main()
