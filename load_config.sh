#!/bin/bash

# load_config.sh
# Helper script to load and validate configuration from config.env

# Function to load configuration
load_config() {
    local config_file="${1:-config.env}"
    
    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: Configuration file '$config_file' not found."
        echo "Please create the configuration file by copying config.env.template to config.env and filling in your values."
        return 1
    fi
    
    # Source the configuration file
    set -a  # automatically export all variables
    source "$config_file"
    set +a  # turn off automatic export
    
    echo "Configuration loaded from: $config_file"
}

# Function to validate required configuration
validate_config() {
    local required_vars=(
        "COMPARTMENT_OCID"
        "EMAIL_SENDER"
        "EMAIL_RECIPIENT"
        "REPORT_BUCKET_NAME"
        "FUNCTION_APP_NAME"
        "NAMESPACE"
    )
    
    # Vault and secrets are required unless we're creating new ones
    if [[ "$CREATE_NEW_VAULT" != "true" ]]; then
        required_vars+=("VAULT_OCID")
        required_vars+=("MASTER_KEY_OCID")
    fi
    
    if [[ "$CREATE_NEW_SECRETS" != "true" ]]; then
        required_vars+=("SMTP_USERNAME_SECRET_OCID")
        required_vars+=("SMTP_PASSWORD_SECRET_OCID")
    fi
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "ERROR: The following required configuration variables are missing or empty:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        echo ""
        echo "Please edit config.env and provide values for all required variables."
        return 1
    fi
    
    echo "Configuration validation passed."
    return 0
}

# Function to prompt for missing configuration values
prompt_for_config() {
    local config_file="${1:-config.env}"
    
    echo "Interactive configuration setup..."
    echo "This will help you fill in the required configuration values."
    echo ""
    
    # Create a temporary file for the new configuration
    local temp_config=$(mktemp)
    cp "$config_file" "$temp_config"
    
    # Required variables to prompt for
    local vars_to_prompt=(
        "COMPARTMENT_OCID:The OCID of the compartment where resources will be created"
        "VAULT_OCID:The OCID of the OCI Vault where secrets are stored"
        "MASTER_KEY_OCID:The OCID of the master encryption key in the vault"
        "SMTP_USERNAME_SECRET_OCID:The OCID of the vault secret containing SMTP username"
        "SMTP_PASSWORD_SECRET_OCID:The OCID of the vault secret containing SMTP password"
        "EMAIL_SENDER:The approved sender email address in OCI Email Delivery"
        "EMAIL_RECIPIENT:The recipient email address for usage reports"
        "NAMESPACE:The Object Storage namespace for your tenancy"
    )
    
    for var_info in "${vars_to_prompt[@]}"; do
        local var_name="${var_info%%:*}"
        local var_description="${var_info#*:}"
        local current_value="${!var_name}"
        
        if [[ -z "$current_value" ]]; then
            echo "Enter $var_description:"
            read -p "$var_name: " new_value
            
            if [[ -n "$new_value" ]]; then
                # Update the configuration file
                sed -i "s|^${var_name}=\".*\"|${var_name}=\"${new_value}\"|" "$temp_config"
            fi
        fi
    done
    
    # Move the temporary file back to the original
    mv "$temp_config" "$config_file"
    echo "Configuration updated in: $config_file"
}

# Function to display current configuration (without sensitive values)
show_config() {
    echo "Current Configuration:"
    echo "  COMPARTMENT_OCID: ${COMPARTMENT_OCID}"
    echo "  VAULT_OCID: ${VAULT_OCID}"
    echo "  MASTER_KEY_OCID: ${MASTER_KEY_OCID}"
    echo "  SMTP_USERNAME_SECRET_OCID: ${SMTP_USERNAME_SECRET_OCID}"
    echo "  SMTP_PASSWORD_SECRET_OCID: ${SMTP_PASSWORD_SECRET_OCID}"
    echo "  EMAIL_SENDER: ${EMAIL_SENDER}"
    echo "  EMAIL_RECIPIENT: ${EMAIL_RECIPIENT}"
    echo "  SMTP_SERVER: ${SMTP_SERVER}"
    echo "  SMTP_PORT: ${SMTP_PORT}"
    echo "  REPORT_BUCKET_NAME: ${REPORT_BUCKET_NAME}"
    echo "  FUNCTION_APP_NAME: ${FUNCTION_APP_NAME}"
    echo "  NAMESPACE: ${NAMESPACE}"
    echo "  REGION: ${REGION}"
    echo "  SUBNET_OCID: ${SUBNET_OCID:-<auto-detect>}"
    
    # Show creation flags if set
    if [[ -n "$CREATE_NEW_VAULT" ]]; then
        echo "  CREATE_NEW_VAULT: ${CREATE_NEW_VAULT}"
    fi
    if [[ -n "$CREATE_NEW_SECRETS" ]]; then
        echo "  CREATE_NEW_SECRETS: ${CREATE_NEW_SECRETS}"
    fi
    
    # Show generated values if available
    if [[ -n "$FUNCTION_APP_OCID" ]]; then
        echo "  FUNCTION_APP_OCID: ${FUNCTION_APP_OCID}"
    fi
    if [[ -n "$FUNCTION_OCID" ]]; then
        echo "  FUNCTION_OCID: ${FUNCTION_OCID}"
    fi
    if [[ -n "$EVENT_RULE_OCID" ]]; then
        echo "  EVENT_RULE_OCID: ${EVENT_RULE_OCID}"
    fi
}

# If script is run directly, provide interactive configuration
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "=== OCI Report Automation Configuration Helper ==="
    
    if [[ "$1" == "--setup" ]]; then
        load_config
        prompt_for_config
        load_config
        validate_config
    elif [[ "$1" == "--validate" ]]; then
        load_config
        validate_config
    elif [[ "$1" == "--show" ]]; then
        load_config
        show_config
    else
        echo "Usage: $0 [--setup|--validate|--show]"
        echo "  --setup    : Interactive configuration setup"
        echo "  --validate : Validate current configuration"
        echo "  --show     : Display current configuration"
        echo ""
        echo "Or source this script in other scripts to use the functions:"
        echo "  source load_config.sh"
        echo "  load_config && validate_config"
    fi
fi
