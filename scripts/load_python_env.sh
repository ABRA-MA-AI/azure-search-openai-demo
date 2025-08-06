#!/bin/sh

. ./scripts/load_python_env.sh

echo 'Running "prepdocs.py" with Storage Account: avivistaiblob'

additionalArgs=""
if [ $# -gt 0 ]; then
  additionalArgs="$@"
fi

# Set your storage account details
STORAGE_ACCOUNT="avivistaiblob"
CONTAINER_NAME="main"  # Change this if your container has a different name

echo "Processing documents from Storage Account: $STORAGE_ACCOUNT"
echo "Container: $CONTAINER_NAME"

# Check if your storage account supports Data Lake Gen2
STORAGE_TYPE=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "rg-AvivistAI" --query "isHnsEnabled" -o tsv 2>/dev/null)

if [ "$STORAGE_TYPE" = "true" ]; then
    echo "Using Data Lake Gen2 approach"
    # Set environment variables for Data Lake Gen2
    export AZURE_ADLS_GEN2_STORAGE_ACCOUNT=$STORAGE_ACCOUNT
    export AZURE_ADLS_GEN2_FILESYSTEM=$CONTAINER_NAME
    export AZURE_ADLS_GEN2_FILESYSTEM_PATH=""
    
    # Run without local file path
    ./.venv/bin/python ./app/backend/prepdocs.py --verbose $additionalArgs
else
    echo "Using regular blob storage approach - downloading files first"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    echo "Temporary directory: $TEMP_DIR"
    
    # Download files from storage
    echo "Downloading files from storage..."
    az storage blob download-batch \
        --destination "$TEMP_DIR" \
        --source "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --pattern "*.pdf" "*.docx" "*.txt" "*.html" "*.json" "*.csv" "*.md" "*.xlsx" "*.pptx" \
        || {
            echo "Download failed or no matching files found"
            rm -rf "$TEMP_DIR"
            exit 1
        }
    
    # Check if files were downloaded
    if [ -z "$(find "$TEMP_DIR" -name "*.*" -type f 2>/dev/null)" ]; then
        echo "No files found in storage container $CONTAINER_NAME"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    echo "Processing downloaded files..."
    ./.venv/bin/python ./app/backend/prepdocs.py "$TEMP_DIR/*" --verbose $additionalArgs
    
    # Cleanup
    rm -rf "$TEMP_DIR"
fi

echo "Done processing files from storage account!"
