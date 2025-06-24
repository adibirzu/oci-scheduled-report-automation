#!/bin/bash

# 06_test_send.sh
# Tests the deployed OCI Function by invoking it with a simulated event.
# This script also performs a local test of the function's core logic.

set -e

echo "--- Testing Deployed Function ---"

# Load configuration if not already loaded
if [[ -z "$COMPARTMENT_OCID" ]]; then
    source load_config.sh
    load_config && validate_config
fi

# Define function name (from func.yaml)
FUNCTION_NAME="send-usage-report"

# --- Local Function Test ---
echo "Starting local test of the function's core logic..."

# We need to run a small Python script to get the latest filename using the func.py logic
# This requires OCI CLI config to be set up locally.
# Ensure Python environment has 'oci' and 'fdk' installed (from requirements.txt)
# This part of the script will execute Python code directly.
LATEST_FILENAME=$(python3 -c "
import os
import sys # Import sys for sys.exit
import io
import json
import oci
from oci.object_storage import ObjectStorageClient
from oci.secrets import SecretsClient # Needed for get_secret
from oci.signer import Signer
from func import handler, get_latest_report_filename, get_secret # Import handler and helper

# Set environment variables for the Python script to mimic OCI Functions environment
os.environ['COMPARTMENT_OCID'] = os.environ.get('COMPARTMENT_OCID')
os.environ['VAULT_OCID'] = os.environ.get('VAULT_OCID')
os.environ['MASTER_KEY_OCID'] = os.environ.get('MASTER_KEY_OCID')
os.environ['EMAIL_SENDER'] = os.environ.get('EMAIL_SENDER')
os.environ['EMAIL_RECIPIENT'] = os.environ.get('EMAIL_RECIPIENT')
os.environ['REPORT_BUCKET_NAME'] = os.environ.get('REPORT_BUCKET_NAME')
os.environ['FUNCTION_APP_NAME'] = os.environ.get('FUNCTION_APP_NAME')
os.environ['SMTP_USERNAME_SECRET_OCID'] = os.environ.get('SMTP_USERNAME_SECRET_OCID')
os.environ['SMTP_PASSWORD_SECRET_OCID'] = os.environ.get('SMTP_PASSWORD_SECRET_OCID')
os.environ['SMTP_SERVER'] = os.environ.get('SMTP_SERVER')
os.environ['SMTP_PORT'] = os.environ.get('SMTP_PORT')
os.environ['NAMESPACE'] = os.environ.get('NAMESPACE', 'frxfz3gch4zb') # Default from func.yaml

# Set up local OCI config and signer for this script
oci_config_path = os.environ.get('OCI_CONFIG_FILE', os.path.expanduser('~/.oci/config'))
oci_profile_name = os.environ.get('OCI_CONFIG_PROFILE', 'DEFAULT')
config = oci.config.from_file(file_location=oci_config_path, profile_name=oci_profile_name)
signer = Signer(
    tenancy=config['tenancy'],
    user=config['user'],
    fingerprint=config['fingerprint'],
    private_key_file_location=config['key_file'],
    pass_phrase=oci.config.get_config_value_or_default(config, 'pass_phrase')
)
oss_client = ObjectStorageClient(config=config, signer=signer)

namespace = os.environ.get('NAMESPACE')
bucket_name = os.environ.get('REPORT_BUCKET_NAME')
report_prefix = 'WeeklyCostsScheduledReport_'

latest_file = get_latest_report_filename(oss_client, namespace, bucket_name, prefix=report_prefix)

if latest_file:
    print(f'Found latest report file: {latest_file}')
    # Simulate the OCI Events payload
    fake_event = {
        'data': {
            'resourceName': latest_file
        }
    }
    payload = io.BytesIO(json.dumps(fake_event).encode('utf-8'))
    
    print(f'Running function handler locally for file: {latest_file}')
    try:
        handler(None, payload) # Context is None for local test
        print('Local function execution completed successfully.')
    except Exception as e:
        print(f'Local function execution failed: {str(e)}')
        sys.exit(1) # Exit with error code
else:
    print(f'No report file found with prefix \"{report_prefix}\" in bucket \"{bucket_name}\". Skipping local function test.')
    sys.exit(1) # Exit with error code if no file found
")

echo "--- Local Function Test Complete ---"
echo ""

# --- Deployed Function Test ---
echo "Starting deployed function test..."

# Get the latest report filename again for invocation
# This part is separate to ensure the local test's success doesn't depend on the deployed function.
LATEST_FILENAME_FOR_INVOKE=$(python3 -c "
import os
import sys # Import sys for sys.exit
import oci
from oci.object_storage import ObjectStorageClient
from oci.signer import Signer
from func import get_latest_report_filename

# Set environment variables for the Python script to mimic OCI Functions environment
os.environ['COMPARTMENT_OCID'] = os.environ.get('COMPARTMENT_OCID')
os.environ['VAULT_OCID'] = os.environ.get('VAULT_OCID')
os.environ['MASTER_KEY_OCID'] = os.environ.get('MASTER_KEY_OCID')
os.environ['EMAIL_SENDER'] = os.environ.get('EMAIL_SENDER')
os.environ['EMAIL_RECIPIENT'] = os.environ.get('EMAIL_RECIPIENT')
os.environ['REPORT_BUCKET_NAME'] = os.environ.get('REPORT_BUCKET_NAME')
os.environ['FUNCTION_APP_NAME'] = os.environ.get('FUNCTION_APP_NAME')
os.environ['SMTP_USERNAME_SECRET_OCID'] = os.environ.get('SMTP_USERNAME_SECRET_OCID')
os.environ['SMTP_PASSWORD_SECRET_OCID'] = os.environ.get('SMTP_PASSWORD_SECRET_OCID')
os.environ['SMTP_SERVER'] = os.environ.get('SMTP_SERVER')
os.environ['SMTP_PORT'] = os.environ.get('SMTP_PORT')
os.environ['NAMESPACE'] = os.environ.get('NAMESPACE', 'frxfz3gch4zb') # Default from func.yaml

oci_config_path = os.environ.get('OCI_CONFIG_FILE', os.path.expanduser('~/.oci/config'))
oci_profile_name = os.environ.get('OCI_CONFIG_PROFILE', 'DEFAULT')
config = oci.config.from_file(file_location=oci_config_path, profile_name=oci_profile_name)
signer = Signer(
    tenancy=config['tenancy'],
    user=config['user'],
    fingerprint=config['fingerprint'],
    private_key_file_location=config['key_file'],
    pass_phrase=oci.config.get_config_value_or_default(config, 'pass_phrase')
)
oss_client = ObjectStorageClient(config=config, signer=signer)

namespace = os.environ.get('NAMESPACE')
bucket_name = os.environ.get('REPORT_BUCKET_NAME')
report_prefix = 'WeeklyCostsScheduledReport_'

latest_file = get_latest_report_filename(oss_client, namespace, bucket_name, prefix=report_prefix)
if latest_file:
    print(latest_file)
else:
    print('')
")

if [[ -z "${LATEST_FILENAME_FOR_INVOKE}" ]]; then
    echo "ERROR: No latest report file found in bucket '${REPORT_BUCKET_NAME}'. Cannot test deployed function."
    echo "Please ensure there are files matching 'WeeklyCostsScheduledReport_*.csv.gz' in the bucket."
    exit 1
fi

echo "Found latest report file for invocation: ${LATEST_FILENAME_FOR_INVOKE}"

# Invoke the function with the latest filename
echo "Invoking function '${FUNCTION_NAME}' in application '${FUNCTION_APP_NAME}' with file '${LATEST_FILENAME_FOR_INVOKE}'..."
echo -n "{\"data\":{\"resourceName\":\"${LATEST_FILENAME_FOR_INVOKE}\"}}" | fn invoke "${FUNCTION_APP_NAME}" "${FUNCTION_NAME}"

echo "Function invocation initiated. Check OCI console for logs and email delivery."

echo "--- Function Testing Complete ---"
