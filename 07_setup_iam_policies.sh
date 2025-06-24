#!/bin/bash

# 07_setup_iam_policies.sh
# Creates Dynamic Groups and IAM policies for OCI Function Resource Principal access

set -e

echo "--- IAM Policies and Dynamic Groups Setup ---"

# Load configuration
source load_config.sh
load_config && validate_config

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

# Get tenancy OCID from OCI config
TENANCY_OCID=$(oci iam compartment get --compartment-id "${COMPARTMENT_OCID}" --query "data.\"compartment-id\"" --raw-output 2>/dev/null || \
               oci iam compartment list --compartment-id-in-subtree false --query "data[0].\"compartment-id\"" --raw-output 2>/dev/null || \
               oci iam region list --query "data[0].name" --raw-output | head -1 | xargs -I {} oci iam tenancy get --tenancy-id {} --query "data.id" --raw-output 2>/dev/null || \
               echo "")

# If we can't get tenancy OCID, we'll proceed without it for dynamic group creation
if [[ -z "$TENANCY_OCID" ]]; then
    echo "Could not determine tenancy OCID automatically. Proceeding with dynamic group creation..."
else
    echo "Tenancy OCID: ${TENANCY_OCID}"
fi

# Define dynamic group name
DYNAMIC_GROUP_NAME="${FUNCTION_APP_NAME}-function-dg"
DYNAMIC_GROUP_DESCRIPTION="Dynamic group for ${FUNCTION_APP_NAME} function application to access OCI resources"

# Check if dynamic group already exists
echo "Checking if dynamic group '${DYNAMIC_GROUP_NAME}' exists..."
EXISTING_DG_OCID=$(oci iam dynamic-group list --all --query "data[?name=='${DYNAMIC_GROUP_NAME}'].id | [0]" --raw-output 2>/dev/null || echo "null")

if [[ "$EXISTING_DG_OCID" != "null" ]] && [[ -n "$EXISTING_DG_OCID" ]]; then
    echo "Dynamic group '${DYNAMIC_GROUP_NAME}' already exists with OCID: ${EXISTING_DG_OCID}"
    DYNAMIC_GROUP_OCID="$EXISTING_DG_OCID"
else
    echo "Creating dynamic group '${DYNAMIC_GROUP_NAME}'..."
    
    # Create matching rule for the function application
    MATCHING_RULE="ALL {resource.type = 'fnfunc', resource.compartment.id = '${COMPARTMENT_OCID}'}"
    
    # If we have a specific function app OCID, make it more specific
    if [[ -n "$FUNCTION_APP_OCID" ]]; then
        MATCHING_RULE="ALL {resource.type = 'fnfunc', resource.compartment.id = '${COMPARTMENT_OCID}', resource.fnapp.id = '${FUNCTION_APP_OCID}'}"
    fi
    
    echo "Matching rule: ${MATCHING_RULE}"
    
    DYNAMIC_GROUP_OCID=$(oci iam dynamic-group create \
        --name "${DYNAMIC_GROUP_NAME}" \
        --description "${DYNAMIC_GROUP_DESCRIPTION}" \
        --matching-rule "${MATCHING_RULE}" \
        --query "data.id" --raw-output)
    
    echo "Dynamic group created with OCID: ${DYNAMIC_GROUP_OCID}"
    update_config_value "DYNAMIC_GROUP_OCID" "${DYNAMIC_GROUP_OCID}"
fi

# Define policy name
POLICY_NAME="${FUNCTION_APP_NAME}-function-policy"
POLICY_DESCRIPTION="IAM policy for ${FUNCTION_APP_NAME} function to access required OCI resources"

# Get the root compartment (tenancy) OCID for policy creation
ROOT_COMPARTMENT_OCID=$(oci iam compartment list --compartment-id-in-subtree false --query "data[0].\"compartment-id\"" --raw-output 2>/dev/null || echo "${COMPARTMENT_OCID}")

echo "Root compartment for policy creation: ${ROOT_COMPARTMENT_OCID}"

# Check if policy already exists (check both compartment and root)
echo "Checking if policy '${POLICY_NAME}' exists..."

# Function to search for policy in a compartment
find_policy_in_compartment() {
    local compartment_id="$1"
    local policy_name="$2"
    
    oci iam policy list --compartment-id "${compartment_id}" --query "data[?name=='${policy_name}'].id | [0]" --raw-output 2>/dev/null || echo "null"
}

# First check in the target compartment
EXISTING_POLICY_OCID=$(find_policy_in_compartment "${COMPARTMENT_OCID}" "${POLICY_NAME}")

# If not found, check at root level
if [[ "$EXISTING_POLICY_OCID" == "null" ]]; then
    EXISTING_POLICY_OCID=$(find_policy_in_compartment "${ROOT_COMPARTMENT_OCID}" "${POLICY_NAME}")
fi

# If still not found, search more broadly by listing all policies and filtering
if [[ "$EXISTING_POLICY_OCID" == "null" ]] || [[ -z "$EXISTING_POLICY_OCID" ]]; then
    echo "Searching for policy across all accessible compartments..."
    
    # Try to find the policy by searching through all policies we can access
    POLICY_SEARCH_RESULT=$(oci iam policy list --compartment-id "${ROOT_COMPARTMENT_OCID}" --all 2>/dev/null | jq -r ".data[] | select(.name == \"${POLICY_NAME}\") | .id" | head -1 2>/dev/null || echo "")
    
    if [[ -n "$POLICY_SEARCH_RESULT" ]] && [[ "$POLICY_SEARCH_RESULT" != "null" ]] && [[ "$POLICY_SEARCH_RESULT" != "" ]]; then
        EXISTING_POLICY_OCID="$POLICY_SEARCH_RESULT"
        echo "Found existing policy with broader search: ${EXISTING_POLICY_OCID}"
    else
        # Final attempt - set to null to ensure we don't have empty string issues
        EXISTING_POLICY_OCID="null"
    fi
fi

if [[ "$EXISTING_POLICY_OCID" != "null" ]] && [[ -n "$EXISTING_POLICY_OCID" ]]; then
    echo "Policy '${POLICY_NAME}' already exists with OCID: ${EXISTING_POLICY_OCID}"
    echo "Checking if policy needs to be updated..."
    
    # Get current policy statements
    CURRENT_STATEMENTS=$(oci iam policy get --policy-id "${EXISTING_POLICY_OCID}" --query "data.statements" --raw-output)
    echo "Current policy statements:"
    echo "${CURRENT_STATEMENTS}" | jq -r '.[]'
    
    # Define the required policy statements
    REQUIRED_STATEMENTS=(
        "Allow dynamic-group ${DYNAMIC_GROUP_NAME} to read objects in compartment id ${COMPARTMENT_OCID} where target.bucket.name = '${REPORT_BUCKET_NAME}'"
        "Allow dynamic-group ${DYNAMIC_GROUP_NAME} to read secret-bundles in compartment id ${COMPARTMENT_OCID} where target.vault.id = '${VAULT_OCID}'"
        "Allow dynamic-group ${DYNAMIC_GROUP_NAME} to use fn-invocation in compartment id ${COMPARTMENT_OCID}"
        "Allow dynamic-group ${DYNAMIC_GROUP_NAME} to read objectstorage-namespaces in tenancy"
        "Allow dynamic-group ${DYNAMIC_GROUP_NAME} to inspect compartments in tenancy"
    )
    
    # Check if all required statements are present
    MISSING_STATEMENTS=()
    for statement in "${REQUIRED_STATEMENTS[@]}"; do
        if ! echo "${CURRENT_STATEMENTS}" | jq -r '.[]' | grep -Fq "$statement"; then
            MISSING_STATEMENTS+=("$statement")
        fi
    done
    
    if [[ ${#MISSING_STATEMENTS[@]} -gt 0 ]]; then
        echo "Policy is missing some required statements. Updating policy..."
        
        # Combine current and missing statements
        ALL_STATEMENTS=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && ALL_STATEMENTS+=("$line")
        done < <(echo "${CURRENT_STATEMENTS}" | jq -r '.[]')
        
        for statement in "${MISSING_STATEMENTS[@]}"; do
            ALL_STATEMENTS+=("$statement")
        done
        
        # Convert to JSON
        POLICY_JSON=$(printf '%s\n' "${ALL_STATEMENTS[@]}" | jq -R . | jq -s .)
        
        echo "Updating policy with missing statements:"
        for statement in "${MISSING_STATEMENTS[@]}"; do
            echo "  + $statement"
        done
        
        # Update the policy
        oci iam policy update \
            --policy-id "${EXISTING_POLICY_OCID}" \
            --statements "${POLICY_JSON}" \
            --force > /dev/null
        
        echo "✅ Policy updated successfully!"
    else
        echo "✅ Policy already contains all required statements."
    fi
    
    POLICY_OCID="${EXISTING_POLICY_OCID}"
    update_config_value "POLICY_OCID" "${POLICY_OCID}"
else
    echo "Creating policy '${POLICY_NAME}' at root compartment level..."
    
    # Define policy statements as an array
    POLICY_STATEMENTS=(
        "Allow dynamic-group ${DYNAMIC_GROUP_NAME} to read objects in compartment id ${COMPARTMENT_OCID} where target.bucket.name = '${REPORT_BUCKET_NAME}'"
        "Allow dynamic-group ${DYNAMIC_GROUP_NAME} to read secret-bundles in compartment id ${COMPARTMENT_OCID} where target.vault.id = '${VAULT_OCID}'"
        "Allow dynamic-group ${DYNAMIC_GROUP_NAME} to use fn-invocation in compartment id ${COMPARTMENT_OCID}"
        "Allow dynamic-group ${DYNAMIC_GROUP_NAME} to read objectstorage-namespaces in tenancy"
        "Allow dynamic-group ${DYNAMIC_GROUP_NAME} to inspect compartments in tenancy"
    )
    
    echo "Policy statements to be created:"
    for statement in "${POLICY_STATEMENTS[@]}"; do
        echo "  - $statement"
    done
    
    # Convert array to JSON format for OCI CLI
    POLICY_JSON=$(printf '%s\n' "${POLICY_STATEMENTS[@]}" | jq -R . | jq -s .)
    
    POLICY_OCID=$(oci iam policy create \
        --compartment-id "${ROOT_COMPARTMENT_OCID}" \
        --name "${POLICY_NAME}" \
        --description "${POLICY_DESCRIPTION}" \
        --statements "${POLICY_JSON}" \
        --query "data.id" --raw-output)
    
    echo "Policy created with OCID: ${POLICY_OCID}"
    update_config_value "POLICY_OCID" "${POLICY_OCID}"
fi

echo ""
echo "=== IAM Setup Summary ==="
echo "Dynamic Group: ${DYNAMIC_GROUP_NAME}"
echo "Dynamic Group OCID: ${DYNAMIC_GROUP_OCID}"
echo "Policy: ${POLICY_NAME}"
echo "Compartment: ${COMPARTMENT_OCID}"
echo ""

echo "=== Permissions Granted ==="
echo "✅ Read objects in bucket '${REPORT_BUCKET_NAME}'"
echo "✅ Read secret bundles from vault '${VAULT_OCID}'"
echo "✅ Use function invocation in compartment"
echo "✅ Read object storage namespaces"
echo "✅ Inspect compartments"
echo ""

echo "=== Verification ==="
echo "You can verify the setup in OCI Console:"
echo "1. Identity & Security > Dynamic Groups > ${DYNAMIC_GROUP_NAME}"
echo "2. Identity & Security > Policies > ${POLICY_NAME}"
echo ""

echo "=== Function Resource Principal ==="
echo "Your function will now be able to use Resource Principal authentication to:"
echo "- Download files from the '${REPORT_BUCKET_NAME}' bucket"
echo "- Retrieve SMTP credentials from vault secrets"
echo "- Send emails using the configured SMTP settings"
echo ""

# Test the dynamic group matching
echo "=== Testing Dynamic Group Matching ==="
if [[ -n "$FUNCTION_OCID" ]]; then
    echo "Testing if function ${FUNCTION_OCID} matches the dynamic group..."
    
    # This is a basic test - in practice, the function will test this when it runs
    echo "Function OCID: ${FUNCTION_OCID}"
    echo "Expected to match rule: ALL {resource.type = 'fnfunc', resource.compartment.id = '${COMPARTMENT_OCID}'}"
    
    # Get the actual function compartment from OCI
    FUNCTION_COMPARTMENT_OCID=$(oci fn function get --function-id "${FUNCTION_OCID}" --query "data.\"compartment-id\"" --raw-output 2>/dev/null || echo "")
    
    if [[ "$FUNCTION_COMPARTMENT_OCID" == "$COMPARTMENT_OCID" ]]; then
        echo "✅ Function compartment matches configuration"
        echo "   Function compartment: $FUNCTION_COMPARTMENT_OCID"
        echo "   Config compartment: $COMPARTMENT_OCID"
    else
        echo "❌ Function compartment does not match configuration"
        echo "   Function compartment: $FUNCTION_COMPARTMENT_OCID"
        echo "   Config compartment: $COMPARTMENT_OCID"
    fi
else
    echo "⚠️  Function OCID not found in config. Deploy the function first."
fi

echo ""
echo "--- IAM Policies and Dynamic Groups Setup Complete ---"
