#!/bin/bash

# 03_vault_secrets_setup.sh
# Creates or uses existing OCI Vault and secrets for SMTP credentials.

set -e

echo "--- Vault Secrets Setup ---"

# Always reload configuration to get the latest values
source load_config.sh
load_config

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

# Function to create a new vault
create_new_vault() {
    echo "Creating new OCI Vault..."
    
    local vault_display_name="OCI Report Automation Vault"
    
    # Create the vault
    local vault_ocid
    echo "Creating vault in compartment ${COMPARTMENT_OCID}..."
    vault_ocid=$(oci kms management vault create \
        --compartment-id "${COMPARTMENT_OCID}" \
        --display-name "${vault_display_name}" \
        --vault-type DEFAULT \
        --wait-for-state ACTIVE \
        --max-wait-seconds 600 \
        --query "data.id" --raw-output)
    
    if [[ -z "$vault_ocid" ]]; then
        echo "ERROR: Failed to create vault"
        return 1
    fi
    
    echo "Vault created with OCID: ${vault_ocid}"
    update_config_value "VAULT_OCID" "${vault_ocid}"
    export VAULT_OCID="${vault_ocid}"
    
    # Wait for vault to be fully ready
    echo "Waiting for vault to be fully ready..."
    sleep 20
    
    # Create master key
    echo "Creating master encryption key..."
    local key_ocid
    local management_endpoint="https://$(echo ${vault_ocid} | cut -d'.' -f5)-management.kms.${REGION}.oraclecloud.com"
    
    key_ocid=$(oci kms management key create \
        --compartment-id "${COMPARTMENT_OCID}" \
        --display-name "oci-report-automation-master-key" \
        --key-shape '{"algorithm":"AES","length":256}' \
        --endpoint "${management_endpoint}" \
        --wait-for-state ENABLED \
        --max-wait-seconds 300 \
        --query "data.id" --raw-output)
    
    if [[ -z "$key_ocid" ]]; then
        echo "ERROR: Failed to create master key"
        return 1
    fi
    
    echo "Master key created with OCID: ${key_ocid}"
    update_config_value "MASTER_KEY_OCID" "${key_ocid}"
    export MASTER_KEY_OCID="${key_ocid}"
    
    echo "Vault and master key created successfully!"
}

# Function to create new secrets
create_new_secrets() {
    echo "Creating new SMTP secrets in vault..."
    
    # Generate unique secret names with timestamp to avoid conflicts
    local timestamp=$(date +%Y%m%d%H%M%S)
    local username_secret_name="smtp-username-secret-${timestamp}"
    local password_secret_name="smtp-password-secret-${timestamp}"
    
    # Wait for vault to be fully ready
    echo "Waiting for vault to be fully ready..."
    sleep 15
    
    # Create SMTP username secret
    echo "Creating SMTP username secret with name: ${username_secret_name}..."
    local username_secret_ocid
    username_secret_ocid=$(oci vault secret create-base64 \
        --compartment-id "${COMPARTMENT_OCID}" \
        --secret-name "${username_secret_name}" \
        --vault-id "${VAULT_OCID}" \
        --key-id "${MASTER_KEY_OCID}" \
        --secret-content-content "$(echo -n "${SMTP_USERNAME}" | base64)" \
        --wait-for-state ACTIVE \
        --max-wait-seconds 300 \
        --query "data.id" --raw-output 2>/dev/null)
    
    if [[ -z "$username_secret_ocid" ]]; then
        echo "ERROR: Failed to create SMTP username secret"
        echo "This might be due to a naming conflict. Trying with a different name..."
        
        # Try with a more unique name
        username_secret_name="smtp-username-${FUNCTION_APP_NAME}-${timestamp}"
        username_secret_ocid=$(oci vault secret create-base64 \
            --compartment-id "${COMPARTMENT_OCID}" \
            --secret-name "${username_secret_name}" \
            --vault-id "${VAULT_OCID}" \
            --key-id "${MASTER_KEY_OCID}" \
            --secret-content-content "$(echo -n "${SMTP_USERNAME}" | base64)" \
            --wait-for-state ACTIVE \
            --max-wait-seconds 300 \
            --query "data.id" --raw-output 2>/dev/null)
        
        if [[ -z "$username_secret_ocid" ]]; then
            echo "ERROR: Failed to create SMTP username secret even with unique name"
            return 1
        fi
    fi
    
    echo "SMTP username secret created with OCID: ${username_secret_ocid}"
    update_config_value "SMTP_USERNAME_SECRET_OCID" "${username_secret_ocid}"
    export SMTP_USERNAME_SECRET_OCID="${username_secret_ocid}"
    
    # Wait between secret creations
    sleep 5
    
    # Create SMTP password secret
    echo "Creating SMTP password secret with name: ${password_secret_name}..."
    local password_secret_ocid
    password_secret_ocid=$(oci vault secret create-base64 \
        --compartment-id "${COMPARTMENT_OCID}" \
        --secret-name "${password_secret_name}" \
        --vault-id "${VAULT_OCID}" \
        --key-id "${MASTER_KEY_OCID}" \
        --secret-content-content "$(echo -n "${SMTP_PASSWORD}" | base64)" \
        --wait-for-state ACTIVE \
        --max-wait-seconds 300 \
        --query "data.id" --raw-output 2>/dev/null)
    
    if [[ -z "$password_secret_ocid" ]]; then
        echo "ERROR: Failed to create SMTP password secret"
        echo "This might be due to a naming conflict. Trying with a different name..."
        
        # Try with a more unique name
        password_secret_name="smtp-password-${FUNCTION_APP_NAME}-${timestamp}"
        password_secret_ocid=$(oci vault secret create-base64 \
            --compartment-id "${COMPARTMENT_OCID}" \
            --secret-name "${password_secret_name}" \
            --vault-id "${VAULT_OCID}" \
            --key-id "${MASTER_KEY_OCID}" \
            --secret-content-content "$(echo -n "${SMTP_PASSWORD}" | base64)" \
            --wait-for-state ACTIVE \
            --max-wait-seconds 300 \
            --query "data.id" --raw-output 2>/dev/null)
        
        if [[ -z "$password_secret_ocid" ]]; then
            echo "ERROR: Failed to create SMTP password secret even with unique name"
            return 1
        fi
    fi
    
    echo "SMTP password secret created with OCID: ${password_secret_ocid}"
    update_config_value "SMTP_PASSWORD_SECRET_OCID" "${password_secret_ocid}"
    export SMTP_PASSWORD_SECRET_OCID="${password_secret_ocid}"
    
    # Clear the plaintext credentials from config for security
    update_config_value "SMTP_USERNAME" ""
    update_config_value "SMTP_PASSWORD" ""
    
    echo "SMTP secrets created successfully!"
}

# Check if we need to create a new vault
if [[ "$CREATE_NEW_VAULT" == "true" ]]; then
    create_new_vault
else
    echo "Using existing vault: ${VAULT_OCID}"
    echo "Using existing master key: ${MASTER_KEY_OCID}"
fi

# Check if we need to create new secrets
if [[ "$CREATE_NEW_SECRETS" == "true" ]]; then
    create_new_secrets
elif [[ -n "$SMTP_USERNAME_SECRET_OCID" ]] && [[ -n "$SMTP_PASSWORD_SECRET_OCID" ]]; then
    echo "Using existing SMTP secrets:"
    echo "  Username secret OCID: ${SMTP_USERNAME_SECRET_OCID}"
    echo "  Password secret OCID: ${SMTP_PASSWORD_SECRET_OCID}"
else
    echo "No SMTP secrets configured and CREATE_NEW_SECRETS is not set to true."
    echo "Please either:"
    echo "1. Set CREATE_NEW_SECRETS=true in config.env to create new secrets"
    echo "2. Provide existing secret OCIDs in config.env"
    exit 1
fi

echo "Vault OCID: ${VAULT_OCID}"
echo "Master Key OCID: ${MASTER_KEY_OCID}"
echo "Please ensure the OCI user/function has 'read secret-bundles' permission for these secrets."

echo "--- Vault Secrets Setup Complete ---"
