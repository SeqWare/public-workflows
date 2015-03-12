#!/usr/bin/env bash
set -o errexit
set -o pipefail

wget https://raw.githubusercontent.com/SeqWare/public-workflows/feature/workflow-DKFZ-EMBL-wrap-workflow/DEWrapperWorkflow/workflow/config/DEWrapperWorkflow.ini
seqware bundle launch --dir /workflows/Workflow_Bundle_DEWrapperWorkflow_1.0-SNAPSHOT_SeqWare_1.1.0-rc.1 --ini DEWrapperWorkflow.ini --engine whitestar --no-metadata
