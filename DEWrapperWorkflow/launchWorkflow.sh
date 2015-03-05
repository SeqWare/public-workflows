#!/usr/bin/env bash
set -o errexit
set -o pipefail

crontab -r
wget https://raw.githubusercontent.com/SeqWare/public-workflows/feature/workflow-DKFZ-EMBL-wrap-workflow/DEWrapperWorkflow/sample.ini
seqware bundle launch --dir /workflows/Workflow_Bundle_DEWrapperWorkflow_1.0-SNAPSHOT_SeqWare_1.1.0-rc.1 --ini sample.ini --engine whitestar
