perl bin/embl_workflow_decider.pl \
--schedule-force-run \
--seqware-clusters cluster.json \
--workflow-version 2.6.0 \
--working-dir small \
--gnos-url  https://gtrepo-etri.annailabs.com  \
--decider-config conf/decider.ini \
--use-cached-analysis \
--schedule-whitelist-donor donors_I_want.txt \
