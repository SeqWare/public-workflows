import boto
import os
import sys
import math
from filechunkio import FileChunkIO

def streamUpload(source, bucket):
    source_path = source
    source_size = os.stat(source_path).st_size
    mp = bucket.initiate_multipart_upload(os.path.basename(source_path))
    chunk_size = 52428800
    chunk_count = int(math.ceil(source_size / float(chunk_size)))
    for i in range(chunk_count):
        offset = chunk_size * i
        bites = min(chunk_size, source_size - offset)
        with FileChunkIO(source_path, 'r', offset=offset, bytes=bites) as fp:
            mp.upload_part_from_file(fp, part_num = i + 1)
        print "%0.2f percent complete ... " % (float(i)/float(chunk_count)*100.0)
    mp.complete_upload()
        

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
                #k = boto.s3.key.Key(bucket)
                #k.name = f
                print "Uploading %s ... " % (os.path.join(path, f))
                streamUpload(os.path.join(path, f), bucket)
                #k.set_contents_from_filename(os.path.join(path, f), replace=True)
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
