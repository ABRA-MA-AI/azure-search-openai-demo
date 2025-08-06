#!/bin/sh

. ./scripts/load_python_env.sh

echo 'Running "prepdocs.py" with Storage Account: avivistaiblob'

additionalArgs=""
if [ $# -gt 0 ]; then
  additionalArgs="$@"
fi

# Your storage account details
STORAGE_ACCOUNT="avivistaiblob"
CONTAINER_NAME="content"
RESOURCE_GROUP="rg-AvivistAI"

echo "Processing documents from Storage Account: $STORAGE_ACCOUNT"

# Check if storage account supports Data Lake Gen2
STORAGE_TYPE=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query "isHnsEnabled" -o tsv 2>/dev/null)

if [ "$STORAGE_TYPE" = "true" ]; then
    echo "Using Data Lake Gen2 approach"
    export AZURE_ADLS_GEN2_STORAGE_ACCOUNT=$STORAGE_ACCOUNT
    export AZURE_ADLS_GEN2_FILESYSTEM=$CONTAINER_NAME
    export AZURE_ADLS_GEN2_FILESYSTEM_PATH=""
    
    ./.venv/bin/python ./app/backend/prepdocs.py --verbose $additionalArgs
else
    echo "Using regular blob storage - downloading files first"
    TEMP_DIR=$(mktemp -d)
    
    # Download files
    az storage blob download-batch \
        --destination "$TEMP_DIR" \
        --source "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login \
        || echo "No files found or download failed"
    
    if [ -n "$(ls -A "$TEMP_DIR" 2>/dev/null)" ]; then
        ./.venv/bin/python ./app/backend/prepdocs.py "$TEMP_DIR/*" --verbose $additionalArgs
        rm -rf "$TEMP_DIR"
    else
        echo "No files to process"
        rm -rf "$TEMP_DIR"
    fi
fi
