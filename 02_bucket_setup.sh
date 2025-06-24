#!/bin/bash

# 02_bucket_setup.sh
# Creates a new OCI Object Storage bucket and configures event rules.

set -e

echo "--- Object Storage Bucket Setup ---"

# Always reload configuration to get the latest values
source load_config.sh
load_config && validate_config

echo "Checking if bucket '${REPORT_BUCKET_NAME}' exists in compartment '${COMPARTMENT_OCID}'..."

# Check if bucket already exists
BUCKET_EXISTS=$(oci os bucket get --name "${REPORT_BUCKET_NAME}" --query "data.name" --raw-output 2>/dev/null || echo "")

if [[ -n "$BUCKET_EXISTS" ]]; then
    echo "Bucket '${REPORT_BUCKET_NAME}' already exists. Skipping creation."
else
    echo "Creating bucket '${REPORT_BUCKET_NAME}'..."
    oci os bucket create \
        --name "${REPORT_BUCKET_NAME}" \
        --compartment-id "${COMPARTMENT_OCID}" \
        --public-access-type NoPublicAccess \
        --storage-tier Standard \
        --metadata '{"purpose": "OCI Usage Reports"}' \
        --events-enabled true \
        --query "data.name" --raw-output >/dev/null
    echo "Bucket '${REPORT_BUCKET_NAME}' created successfully."
fi

# Enable events for the bucket
echo "Enabling events for bucket '${REPORT_BUCKET_NAME}'..."
# Note: OCI Events are typically configured via the Events service, not directly on the bucket.
# We will create an Event Rule later that triggers the function when an object is created in this bucket.
echo "Event configuration will be handled by creating an Event Rule in a later step (05_function_deploy.sh or a separate event setup script)."

echo "--- Object Storage Bucket Setup Complete ---"
