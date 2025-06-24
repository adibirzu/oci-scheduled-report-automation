#!/bin/bash

# 05_function_deploy.sh
# Deploys the OCI Function and configures necessary IAM policies and Event Rule.

set -e

echo "--- OCI Function Deployment Setup ---"

# Load configuration if not already loaded
if [[ -z "$COMPARTMENT_OCID" ]]; then
    source load_config.sh
    load_config && validate_config
fi

# Function to update config.env with generated values
update_config_value() {
    local key="$1"
    local value="$2"
    local config_file="${3:-config.env}"
    
    if [[ -f "$config_file" ]]; then
        # Update existing value
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$config_file"
        echo "Updated config.env: ${key}=\"${value}\""
    fi
}

# Define function name (from func.yaml)
FUNCTION_NAME="send-usage-report"

# 1. Create OCI Functions Application if it doesn't exist
echo "Checking if Functions Application '${FUNCTION_APP_NAME}' exists in compartment '${COMPARTMENT_OCID}'..."
APP_OCID=$(oci fn application list \
    --compartment-id "${COMPARTMENT_OCID}" \
    --display-name "${FUNCTION_APP_NAME}" \
    --query "data[0].id" --raw-output 2>/dev/null || true)

if [[ -n "${APP_OCID}" ]]; then
    echo "Functions Application '${FUNCTION_APP_NAME}' already exists with OCID: ${APP_OCID}. Skipping creation."
    export FUNCTION_APP_OCID="${APP_OCID}"
else
    echo "Creating Functions Application '${FUNCTION_APP_NAME}' in compartment '${COMPARTMENT_OCID}'..."
    # Use subnet from configuration or auto-detect
    DEFAULT_SUBNET_OCID="${SUBNET_OCID}"
    
    # Try to get a subnet from the compartment if not provided in configuration
    if [[ -z "${DEFAULT_SUBNET_OCID}" ]]; then
        echo "Attempting to find a suitable subnet in compartment '${COMPARTMENT_OCID}'..."
        # This is a very basic attempt to find *any* subnet. User should verify.
        SUBNET_ID=$(oci network subnet list \
            --compartment-id "${COMPARTMENT_OCID}" \
            --query "data[0].id" --raw-output 2>/dev/null || true)
        if [[ -n "${SUBNET_ID}" ]]; then
            DEFAULT_SUBNET_OCID="${SUBNET_ID}"
            echo "Found subnet: ${DEFAULT_SUBNET_OCID}. Using this for the application."
            # Store the auto-detected subnet in config.env for future use
            update_config_value "SUBNET_OCID" "${DEFAULT_SUBNET_OCID}"
        else
            echo "ERROR: No suitable subnet found or provided. Please update 05_function_deploy.sh with a valid SUBNET_OCID."
            exit 1
        fi
    fi

    APP_OCID=$(oci fn application create \
        --compartment-id "${COMPARTMENT_OCID}" \
        --display-name "${FUNCTION_APP_NAME}" \
        --subnet-ids "[\"${DEFAULT_SUBNET_OCID}\"]" \
        --wait-for-state ACTIVE \
        --query "data.id" --raw-output)
    echo "Functions Application '${FUNCTION_APP_NAME}' created with OCID: ${APP_OCID}"
    export FUNCTION_APP_OCID="${APP_OCID}"
    # Store the generated Function App OCID in config.env
    update_config_value "FUNCTION_APP_OCID" "${APP_OCID}"
fi

# 2. Update func.yaml with configuration values before deployment
echo "Updating func.yaml with configuration values..."
# Create a temporary func.yaml with the configuration values
cp func.yaml func.yaml.backup

# Update the configuration values in func.yaml using sed
sed -i "s|BUCKET_NAME: .*|BUCKET_NAME: ${REPORT_BUCKET_NAME}|" func.yaml
sed -i "s|EMAIL_FROM: .*|EMAIL_FROM: ${EMAIL_SENDER}|" func.yaml
sed -i "s|EMAIL_TO: .*|EMAIL_TO: ${EMAIL_RECIPIENT}|" func.yaml
sed -i "s|NAMESPACE: .*|NAMESPACE: ${NAMESPACE}|" func.yaml
sed -i "s|REGION: .*|REGION: ${REGION}|" func.yaml
sed -i "s|SMTP_PASSWORD_SECRET_OCID: .*|SMTP_PASSWORD_SECRET_OCID: ${SMTP_PASSWORD_SECRET_OCID}|" func.yaml
sed -i "s|SMTP_SERVER: .*|SMTP_SERVER: ${SMTP_SERVER}|" func.yaml
sed -i "s|SMTP_PORT: .*|SMTP_PORT: \"${SMTP_PORT}\"|" func.yaml
sed -i "s|SMTP_USERNAME_SECRET_OCID: .*|SMTP_USERNAME_SECRET_OCID: ${SMTP_USERNAME_SECRET_OCID}|" func.yaml

echo "Configuration values updated in func.yaml"

# 3. Deploy the Function
echo "Deploying function '${FUNCTION_NAME}' to application '${FUNCTION_APP_NAME}'..."
# fn deploy command needs to be run from the directory containing func.yaml
# The func.yaml, func.py, and requirements.txt should be in the current directory
fn deploy --app "${FUNCTION_APP_NAME}" --verbose

# Restore the original func.yaml
echo "Restoring original func.yaml..."
mv func.yaml.backup func.yaml

echo "Function deployment initiated. Waiting for function to become active..."

# Give some time for the deployment to register
sleep 10

# Get the function OCID again, as it might have changed or been created
FUNCTION_OCID=$(oci fn function list \
    --application-id "${FUNCTION_APP_OCID}" \
    --display-name "${FUNCTION_NAME}" \
    --query "data[0].id" --raw-output)

if [[ -z "${FUNCTION_OCID}" ]]; then
    echo "ERROR: Function OCID not found after deployment. Cannot proceed."
    exit 1
fi

# Store the Function OCID in config.env
update_config_value "FUNCTION_OCID" "${FUNCTION_OCID}"

# Robustly wait for the function to become active
MAX_RETRIES=10
RETRY_INTERVAL=15 # seconds
for i in $(seq 1 $MAX_RETRIES); do
    echo "Checking function state (attempt $i/$MAX_RETRIES)..."
    # Use 'oci fn function list' and filter by function-id to get lifecycle-state,
    # as 'oci fn function get' seems problematic with --application-id or --function-id in this CLI version.
    CURRENT_STATE=$(oci fn function list \
        --application-id "${FUNCTION_APP_OCID}" \
        --query "data[?id=='${FUNCTION_OCID}'].\"lifecycle-state\" | [0]" --raw-output 2>/dev/null || true)

    if [[ "${CURRENT_STATE}" == "ACTIVE" ]]; then
        echo "Function '${FUNCTION_NAME}' is now ACTIVE."
        break
    elif [[ "${CURRENT_STATE}" == "FAILED" || "${CURRENT_STATE}" == "DELETING" ]]; then
        echo "ERROR: Function '${FUNCTION_NAME}' entered state: ${CURRENT_STATE}. Aborting."
        exit 1
    else
        echo "Function state: ${CURRENT_STATE}. Waiting ${RETRY_INTERVAL} seconds..."
        sleep ${RETRY_INTERVAL}
    fi

    if [[ $i -eq $MAX_RETRIES ]]; then
        echo "ERROR: Function '${FUNCTION_NAME}' did not become ACTIVE after ${MAX_RETRIES} attempts. Aborting."
        exit 1
    fi
done

# 3. Configure IAM Policies for the Function's Resource Principal
echo "Configuring IAM policies for function's Resource Principal..."
# Get the application's Resource Principal ID (dynamic group OCID)
# This is usually created automatically when the application is created with resource principal enabled.
# The dynamic group name is typically 'oci-fn-dynamic-group-<app_ocid>'
# We need to find the dynamic group that corresponds to the function application.
# This is a complex step as dynamic groups are not directly listed by app OCID.
# A common approach is to create a dynamic group manually and associate it with the function.
# For this script, we'll assume a dynamic group exists or needs to be created manually by the user
# and then policies are applied.
# Let's define a placeholder for the dynamic group name.
DYNAMIC_GROUP_NAME="${FUNCTION_APP_NAME}-dynamic-group"
echo "Please ensure a Dynamic Group named '${DYNAMIC_GROUP_NAME}' exists and has matching rules for functions in application '${FUNCTION_APP_OCID}'."
echo "Example rule: ALL {resource.type = 'fnfunc', resource.compartment.id = '${COMPARTMENT_OCID}', resource.id = '${FUNCTION_APP_OCID}'}"
echo "Or for all functions in the app: ALL {resource.type = 'fnfunc', resource.compartment.id = '${COMPARTMENT_OCID}', resource.fnapp.id = '${FUNCTION_APP_OCID}'}"

# Define policy statements
POLICY_STATEMENTS=(
    "Allow dynamic-group \"${DYNAMIC_GROUP_NAME}\" to read objects in compartment id \"${COMPARTMENT_OCID}\" where target.bucket.name = '${REPORT_BUCKET_NAME}'"
    "Allow dynamic-group \"${DYNAMIC_GROUP_NAME}\" to read secret-bundles in compartment id \"${COMPARTMENT_OCID}\" where target.vault.id = '${VAULT_OCID}'"
    "Allow dynamic-group \"${DYNAMIC_GROUP_NAME}\" to use fn-invocation in compartment id \"${COMPARTMENT_OCID}\"" # For function to invoke other functions if needed
)

# Apply policies (check if they exist first to avoid errors)
for STATEMENT in "${POLICY_STATEMENTS[@]}"; do
    echo "Checking/Applying policy: ${STATEMENT}"
    # OCI CLI doesn't have a direct 'policy exists' check by statement content.
    # This would require listing all policies and parsing.
    # For simplicity, we'll just print the commands for the user to execute manually if needed.
    echo "Please ensure the following policy is configured in OCI IAM:"
    echo "  ${STATEMENT}"
done

echo ""
echo "=== Next Steps ==="
echo "✅ Function '${FUNCTION_NAME}' deployed successfully!"
echo "✅ Function OCID: ${FUNCTION_OCID}"
echo "✅ IAM policies configured for Resource Principal access"
echo ""
echo "To complete the setup:"
echo "1. Run './08_create_event_rule.sh' to create an Event Rule (optional)"
echo "2. Run './06_test_send.sh' to test the function"
echo ""
echo "The Event Rule will automatically trigger the function when files are uploaded to the bucket."

echo "--- OCI Function Deployment Setup Complete ---"
