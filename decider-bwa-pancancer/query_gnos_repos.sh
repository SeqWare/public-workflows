#!/bin/bash

# queries each gnos repo

for i in gtrepo-bsc gtrepo-dkfz gtrepo-osdc gtrepo-etri gtrepo-ebi; do 
echo $i; 
  perl workflow_decider.pl --gnos-url https://$i.annailabs.com --report $i.log --ignore-lane-count --upload-results --test
  echo "SITE: $i";
  cat $i.log | grep 'ALIGNMENT:' | sort | uniq -c
done;

