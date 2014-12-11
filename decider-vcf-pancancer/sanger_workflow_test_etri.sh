perl bin/sanger_workflow_decider.pl \
--schedule-force-run \
--seqware-clusters cluster.json \
--bwa-workflow-version 2.6.0 \
--workflow-version 1.0.1 \
--working-dir etri \
--gnos-url  https://gtrepo-etri.annailabs.com \
--decider-config conf/decider.ini \
--use-cached-analysis \
--schedule-whitelist-donor donors_I_want.txt \

#https://gtrepo-etri.annailabs.com  \
#https://gtrepo-osdc-icgc.annailabs.com
