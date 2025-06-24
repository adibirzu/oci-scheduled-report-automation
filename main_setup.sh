#!/bin/bash

# main_setup.sh
# This script orchestrates the setup of OCI services for usage report automation.
# It will automatically populate config.env with user input and generated values.

set -e

echo "Starting OCI Report Automation Setup..."

# Load configuration helper functions
source load_config.sh

# Function to update config.env with a new value
update_config_value() {
    local key="$1"
    local value="$2"
    local config_file="${3:-config.env}"
    
    if [[ -f "$config_file" ]]; then
        # Update existing value
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$config_file"
    else
        # Append new value
        echo "${key}=\"${value}\"" >> "$config_file"
    fi
    echo "Updated config.env: ${key}=\"${value}\""
}

# Function to get user input for configuration
get_user_input() {
    local prompt="$1"
    local var_name="$2"
    local current_value="$3"
    local is_required="$4"
    
    if [[ -n "$current_value" ]]; then
        echo "Current value for ${var_name}: ${current_value}"
        read -p "${prompt} (press Enter to keep current value): " new_value
        if [[ -z "$new_value" ]]; then
            new_value="$current_value"
        fi
    else
        while true; do
            read -p "${prompt}: " new_value
            if [[ -n "$new_value" ]] || [[ "$is_required" != "true" ]]; then
                break
            fi
            echo "This field is required. Please provide a value."
        done
    fi
    
    if [[ -n "$new_value" ]]; then
        update_config_value "$var_name" "$new_value"
        export "$var_name"="$new_value"
    fi
}

# Function to auto-detect and populate namespace
detect_namespace() {
    echo "Detecting Object Storage namespace..."
    local detected_namespace
    detected_namespace=$(oci os ns get --query "data" --raw-output 2>/dev/null || true)
    
    if [[ -n "$detected_namespace" ]]; then
        echo "Auto-detected namespace: $detected_namespace"
        update_config_value "NAMESPACE" "$detected_namespace"
        export NAMESPACE="$detected_namespace"
        return 0
    else
        echo "Could not auto-detect namespace. You will need to provide it manually."
        return 1
    fi
}

# Initialize configuration file if it doesn't exist
if [[ ! -f "config.env" ]]; then
    echo "Creating config.env file..."
    cp config.env config.env 2>/dev/null || cat > config.env << 'EOF'
# OCI Report Automation Configuration File
# This file contains all the tenancy and data-specific variables needed for the automation
# Values will be populated automatically during setup

# =============================================================================
# COMPARTMENT AND TENANCY INFORMATION
# =============================================================================
COMPARTMENT_OCID=""

# =============================================================================
# VAULT AND SECURITY INFORMATION
# =============================================================================
VAULT_OCID=""
MASTER_KEY_OCID=""
SMTP_USERNAME_SECRET_OCID=""
SMTP_PASSWORD_SECRET_OCID=""

# =============================================================================
# EMAIL CONFIGURATION
# =============================================================================
EMAIL_SENDER=""
EMAIL_RECIPIENT=""
SMTP_SERVER="smtp.email.eu-frankfurt-1.oci.oraclecloud.com"
SMTP_PORT="587"

# =============================================================================
# STORAGE AND FUNCTION CONFIGURATION
# =============================================================================
REPORT_BUCKET_NAME="monthly-usage-reports"
FUNCTION_APP_NAME="usagereports"

# =============================================================================
# OCI TENANCY SPECIFIC INFORMATION
# =============================================================================
NAMESPACE=""
REGION="eu-frankfurt-1"

# =============================================================================
# NETWORK CONFIGURATION (Optional - will be auto-detected if not provided)
# =============================================================================
SUBNET_OCID=""
EOF
fi

# Load existing configuration
load_config 2>/dev/null || true

echo ""
echo "=== Interactive Configuration Setup ==="
echo "This script will help you configure the OCI Report Automation."
echo "You can press Enter to keep existing values or provide new ones."
echo ""

# Execute prerequisite check first
echo "Executing 01_prerequisites_check.sh..."
bash 01_prerequisites_check.sh
echo ""

# Collect configuration from user
echo "=== Tenancy Information ==="
get_user_input "Enter the OCID of the compartment where resources will be created" "COMPARTMENT_OCID" "$COMPARTMENT_OCID" "true"

# Auto-detect namespace
if [[ -z "$NAMESPACE" ]]; then
    if ! detect_namespace; then
        get_user_input "Enter your Object Storage namespace" "NAMESPACE" "$NAMESPACE" "true"
    fi
else
    echo "Using existing namespace: $NAMESPACE"
fi

echo ""
echo "=== Vault and Security Configuration ==="

# Ask about vault setup preference
if [[ -z "$VAULT_OCID" ]]; then
    echo "Do you want to:"
    echo "1. Use an existing OCI Vault"
    echo "2. Create a new OCI Vault"
    read -p "Choose option (1 or 2): " vault_choice
    
    case $vault_choice in
        1)
            get_user_input "Enter the OCID of the existing OCI Vault" "VAULT_OCID" "$VAULT_OCID" "true"
            get_user_input "Enter the OCID of the master encryption key in the vault" "MASTER_KEY_OCID" "$MASTER_KEY_OCID" "true"
            ;;
        2)
            echo "Creating new OCI Vault and master key..."
            # This will be handled by an enhanced vault setup script
            CREATE_NEW_VAULT="true"
            update_config_value "CREATE_NEW_VAULT" "$CREATE_NEW_VAULT"
            ;;
        *)
            echo "Invalid choice. Please run the script again and choose 1 or 2."
            exit 1
            ;;
    esac
else
    echo "Using existing vault: $VAULT_OCID"
    if [[ -z "$MASTER_KEY_OCID" ]]; then
        get_user_input "Enter the OCID of the master encryption key in the vault" "MASTER_KEY_OCID" "$MASTER_KEY_OCID" "true"
    fi
fi

# Ask about SMTP secrets setup preference
if [[ -z "$SMTP_USERNAME_SECRET_OCID" ]] || [[ -z "$SMTP_PASSWORD_SECRET_OCID" ]]; then
    echo ""
    echo "Do you want to:"
    echo "1. Use existing SMTP secrets in the vault"
    echo "2. Create new SMTP secrets in the vault"
    read -p "Choose option (1 or 2): " secrets_choice
    
    case $secrets_choice in
        1)
            get_user_input "Enter the OCID of the vault secret containing SMTP username" "SMTP_USERNAME_SECRET_OCID" "$SMTP_USERNAME_SECRET_OCID" "true"
            get_user_input "Enter the OCID of the vault secret containing SMTP password" "SMTP_PASSWORD_SECRET_OCID" "$SMTP_PASSWORD_SECRET_OCID" "true"
            # Ensure we don't create new secrets
            update_config_value "CREATE_NEW_SECRETS" "false"
            ;;
        2)
            echo "New SMTP secrets will be created in the vault..."
            echo ""
            echo "First, let's create the SMTP user credentials that will be stored in the vault."
            echo "Do you want to:"
            echo "  a) Use existing SMTP credentials"
            echo "  b) Create new SMTP user in OCI Email Delivery"
            read -p "Choose option (a or b): " smtp_user_choice
            
            case $smtp_user_choice in
                a)
                    echo "Using existing SMTP credentials..."
                    read -p "Enter SMTP username: " smtp_username
                    read -s -p "Enter SMTP password: " smtp_password
                    echo ""
                    ;;
                b)
                    echo "Creating new SMTP user in OCI Email Delivery..."
                    echo "This will create a new SMTP user for the approved sender email."
                    
                    # Create SMTP user
                    echo "Creating SMTP user for email: ${EMAIL_SENDER}"
                    smtp_user_result=$(oci email smtp-credential create \
                        --user-id "$(oci iam user list --query "data[?name=='$(whoami)'].id | [0]" --raw-output 2>/dev/null || oci iam user list --query "data[0].id" --raw-output)" \
                        --description "SMTP credentials for OCI Report Automation" \
                        --query "data.{username:username,password:password}" \
                        --output json 2>/dev/null || true)
                    
                    if [[ -n "$smtp_user_result" ]]; then
                        smtp_username=$(echo "$smtp_user_result" | jq -r '.username')
                        smtp_password=$(echo "$smtp_user_result" | jq -r '.password')
                        echo "SMTP user created successfully!"
                        echo "Username: $smtp_username"
                        echo "Password: [hidden for security]"
                        echo ""
                        echo "IMPORTANT: Save these credentials securely. The password cannot be retrieved again."
                        read -p "Press Enter to continue after you've saved the credentials..."
                    else
                        echo "Failed to create SMTP user automatically. Please create one manually in OCI Console."
                        echo "Go to: Identity & Security > Users > [Your User] > SMTP Credentials"
                        echo "Then enter the credentials below:"
                        read -p "Enter SMTP username: " smtp_username
                        read -s -p "Enter SMTP password: " smtp_password
                        echo ""
                    fi
                    ;;
                *)
                    echo "Invalid choice. Using manual credential entry..."
                    read -p "Enter SMTP username: " smtp_username
                    read -s -p "Enter SMTP password: " smtp_password
                    echo ""
                    ;;
            esac
            
            # Store credentials for vault creation script
            update_config_value "SMTP_USERNAME" "$smtp_username"
            update_config_value "SMTP_PASSWORD" "$smtp_password"
            update_config_value "CREATE_NEW_SECRETS" "true"
            ;;
        *)
            echo "Invalid choice. Please run the script again and choose 1 or 2."
            exit 1
            ;;
    esac
else
    echo "Using existing SMTP secrets:"
    echo "  Username secret: $SMTP_USERNAME_SECRET_OCID"
    echo "  Password secret: $SMTP_PASSWORD_SECRET_OCID"
fi

echo ""
echo "=== Email Configuration ==="
get_user_input "Enter the approved sender email address (configured in OCI Email Delivery)" "EMAIL_SENDER" "$EMAIL_SENDER" "true"
get_user_input "Enter the recipient email address for usage reports" "EMAIL_RECIPIENT" "$EMAIL_RECIPIENT" "true"

echo ""
echo "=== Resource Names (Optional - defaults provided) ==="
get_user_input "Enter the name for the Object Storage bucket" "REPORT_BUCKET_NAME" "$REPORT_BUCKET_NAME" "false"
get_user_input "Enter the name for the OCI Functions application" "FUNCTION_APP_NAME" "$FUNCTION_APP_NAME" "false"

echo ""
echo "=== Network Configuration (Optional) ==="

# Function to discover and display available subnets
discover_subnets() {
    echo "Discovering available subnets in compartment..."
    
    # Get all VCNs in the compartment (show only names for readability)
    local vcns
    vcns=$(oci network vcn list --compartment-id "${COMPARTMENT_OCID}" --query "data[].\"display-name\"" --output table 2>/dev/null || true)
    
    if [[ -z "$vcns" ]] || [[ "$vcns" == "[]" ]]; then
        echo "No VCNs found in compartment ${COMPARTMENT_OCID}"
        return 1
    fi
    
    echo "Available VCNs in compartment:"
    echo "$vcns"
    echo ""
    
    # Get VCN name to OCID mapping for subnet display
    local vcn_mapping
    vcn_mapping=$(oci network vcn list --compartment-id "${COMPARTMENT_OCID}" --query "data[].{id:id,name:\"display-name\"}" --output json 2>/dev/null || true)
    
    # Get all subnets in the compartment with VCN names instead of OCIDs
    local subnets_raw
    subnets_raw=$(oci network subnet list --compartment-id "${COMPARTMENT_OCID}" --query "data[].{OCID:id,Name:\"display-name\",VCN_OCID:\"vcn-id\",CIDR:\"cidr-block\",State:\"lifecycle-state\"}" --output json 2>/dev/null || true)
    
    # Process subnets to replace VCN OCIDs with names
    local subnets
    if [[ -n "$subnets_raw" ]] && [[ "$subnets_raw" != "[]" ]]; then
        subnets=$(echo "$subnets_raw" | jq -r --argjson vcns "$vcn_mapping" '
            map(
                . as $subnet |
                ($vcns[] | select(.id == $subnet.VCN_OCID).name) as $vcn_name |
                {
                    OCID: .OCID,
                    Name: .Name,
                    VCN: ($vcn_name // .VCN_OCID),
                    CIDR: .CIDR,
                    State: .State
                }
            )' | jq -r '(["OCID","Name","VCN","CIDR","State"] | @tsv), (.[] | [.OCID, .Name, .VCN, .CIDR, .State] | @tsv)' | column -t)
    fi
    
    if [[ -z "$subnets" ]] || [[ "$subnets" == "[]" ]]; then
        echo "No subnets found in compartment ${COMPARTMENT_OCID}"
        return 1
    fi
    
    echo "Available subnets in compartment:"
    echo "$subnets"
    echo ""
    
    return 0
}

# Check if user wants to see available subnets
if [[ -z "$SUBNET_OCID" ]]; then
    echo "Do you want to:"
    echo "1. See available subnets in the compartment"
    echo "2. Enter a subnet OCID manually"
    echo "3. Skip (auto-detect during deployment)"
    read -p "Choose option (1, 2, or 3): " subnet_choice
    
    case $subnet_choice in
        1)
            if discover_subnets; then
                echo "Please copy the OCID of the subnet you want to use from the list above."
                get_user_input "Enter the OCID of the subnet for the function application" "SUBNET_OCID" "$SUBNET_OCID" "false"
            else
                echo "Could not discover subnets. You can enter a subnet OCID manually or skip for auto-detection."
                get_user_input "Enter the OCID of the subnet for the function application (leave empty for auto-detection)" "SUBNET_OCID" "$SUBNET_OCID" "false"
            fi
            ;;
        2)
            get_user_input "Enter the OCID of the subnet for the function application" "SUBNET_OCID" "$SUBNET_OCID" "false"
            ;;
        3)
            echo "Subnet will be auto-detected during deployment."
            ;;
        *)
            echo "Invalid choice. Subnet will be auto-detected during deployment."
            ;;
    esac
else
    echo "Using existing subnet: $SUBNET_OCID"
    echo "Do you want to change it? (y/n)"
    read -p "Change subnet? " change_subnet
    if [[ "$change_subnet" =~ ^[Yy]$ ]]; then
        if discover_subnets; then
            echo "Please copy the OCID of the subnet you want to use from the list above."
        fi
        get_user_input "Enter the OCID of the subnet for the function application (leave empty for auto-detection)" "SUBNET_OCID" "$SUBNET_OCID" "false"
    fi
fi

# Reload configuration to ensure all values are available
load_config

echo ""
echo "=== Configuration Summary ==="
show_config
echo ""

read -p "Do you want to proceed with the setup using this configuration? (y/n): " proceed_choice
if [[ ! "$proceed_choice" =~ ^[Yy]$ ]]; then
    echo "Setup cancelled. You can edit config.env manually and run this script again."
    exit 0
fi

# Execute setup steps
echo "Executing 02_bucket_setup.sh..."
bash 02_bucket_setup.sh

echo "Executing 03_vault_secrets_setup.sh..."
bash 03_vault_secrets_setup.sh

echo "Executing 04_email_delivery_setup.sh..."
bash 04_email_delivery_setup.sh

echo "Executing 05_function_deploy.sh..."
bash 05_function_deploy.sh

echo "Executing 07_setup_iam_policies.sh..."
bash 07_setup_iam_policies.sh

echo ""
echo "=== Event Rule Setup (Optional) ==="
echo "Do you want to create an Event Rule to automatically trigger the function when files are uploaded?"
read -p "Create Event Rule? (y/n): " create_event_rule_choice

if [[ "$create_event_rule_choice" =~ ^[Yy]$ ]]; then
    echo "Executing 08_create_event_rule.sh..."
    bash 08_create_event_rule.sh
else
    echo "Skipping Event Rule creation. You can create it later by running: ./08_create_event_rule.sh"
fi

echo "Executing 06_test_send.sh..."
bash 06_test_send.sh

echo ""
echo "=========================================="
echo "OCI Report Automation Setup Complete!"
echo "=========================================="
echo ""

# Reload configuration to show final state including generated values
load_config

echo "=== Final Configuration Summary ==="
show_config
echo ""

echo "=== Setup Summary ==="
echo " Prerequisites checked"
echo " Object Storage bucket '${REPORT_BUCKET_NAME}' configured"
echo " Vault secrets validated"
echo " Email delivery configured"
echo " Function '${FUNCTION_NAME}' deployed to application '${FUNCTION_APP_NAME}'"
echo " Event rule created for automatic triggering"
echo " Configuration saved to config.env"
echo ""

echo "=== Next Steps ==="
echo "1. Ensure Dynamic Group and IAM policies are configured as shown during deployment"
echo "2. Upload a usage report file to bucket '${REPORT_BUCKET_NAME}' to test the automation"
echo "3. Check OCI Console for function logs and email delivery status"
echo "4. Your configuration is saved in config.env for future use"
echo ""

echo "Setup completed successfully! 🎉"
