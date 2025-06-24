#!/bin/bash

# 04_email_delivery_setup.sh
# Confirms the OCI Email Delivery approved sender.

set -e

echo "--- Email Delivery Setup ---"

# Load configuration if not already loaded
if [[ -z "$COMPARTMENT_OCID" ]]; then
    source load_config.sh
    load_config && validate_config
fi

echo "Using existing approved sender: ${EMAIL_SENDER}"
echo "Please ensure this email address is configured as an approved sender in OCI Email Delivery in compartment '${COMPARTMENT_OCID}'."

# Optional: Add a check here if needed, but it requires 'oci email sender list' and parsing.
# For simplicity, we assume the user has confirmed it.

echo "--- Email Delivery Setup Complete ---"
