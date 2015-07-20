# Python download checker

import hashlib
import os
import sys
import urllib2
import xml.dom.minidom

def main(url, md5):
    
    # Fetch Metadata
    response = urllib2.urlopen(url)
    data = response.read()
    response.close()
    XML = xml.dom.minidom.parseString(data);
    
    # Create a list of expected files
    filelist = []
    for subelement in XML.getElementsByTagName('file'):
        filelist.append(subelement.getElementsByTagName('filename')[0].firstChild.nodeValue)
    
    # Verify the existence of each file
    folder = url.split("analysisFull/")[1].replace("/","")
    
    valid = True
    for f in filelist:
        if not os.path.exists(os.path.join(folder,f)):
            valid = False

    # Verify the md5sum of the file
    datasplit = data.split('\n')
    datasplit[1] = "<ResultSet>"
    data = "\n".join(datasplit).rstrip()
    hasher = hashlib.md5()
    hasher.update(data)
    myhash=hasher.hexdigest()

    # Store the downloaded xml
    with open("patched.xml","w") as f:
	f.write(data)

    if md5 != myhash:
	valid = False
	print "ERROR: The xml data downloaded from %s does not match the pregenerated data!" % sys.argv[1]
	print >> sys.stderr, "ERROR: The xml data downloaded from %s does not match the pregenerated data!" % sys.argv[1]
        
    if valid:
        sys.exit(0)
    sys.exit(1)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

# USAGE: python download_check.py [https://metadataURL] [md5sum of xml]


