# BWA Decider

## About

This is the decider for the PanCancer Variant Calling workfow.


## Installing dependencies
A shell script named 'install' will install all of the dependencies.

$ sudo bash install

## Configuration
./conf/decider.ini contains the decoder parameters
./conf/ini contains templates for workflow setting and ini files

## White/Black lists
Place donor and sample-level white or black lists in the appropriate directory.
For example a white list of donor IDs is placed in the whitelist directory, then
specified as follows:

whitelist-donor=donors_I_want.txt

Other options:
blacklist-donor=
whitelist-sample=
blacklist-sample=

Each list is a text file with one donor or sample ID/line

## Testing
There is a shell script 'sanger_decider_test.sh' that will run the decider through its paces.

# To test on itri GNOS repo
bash sanger_workflow_test_itri.sh

# To test on osdc GNOS repo
bash sanger_workflow_test_osdc.sh


