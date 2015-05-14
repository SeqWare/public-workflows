# Python download checker

import os
import sys
import urllib2
import xml.dom.minidom

def main(url):
    
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
        
    if valid:
        sys.exit(0)
    sys.exit(1)

if __name__ == '__main__':
    main(sys.argv[1])
