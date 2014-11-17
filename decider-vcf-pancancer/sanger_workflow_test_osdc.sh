perl bin/sanger_workflow_decider.pl \
--schedule-force-run \
--seqware-clusters cluster.json \
--workflow-version 2.6.0 \
--working-dir osdc \
--gnos-url  https://gtrepo-osdc-icgc.annailabs.com \
--decider-config conf/decider.ini \
--use-cached-analysis 

#--schedule-whitelist-donor donors_I_want.txt \

#https://gtrepo-etri.annailabs.com  \
#https://gtrepo-osdc-icgc.annailabs.com
