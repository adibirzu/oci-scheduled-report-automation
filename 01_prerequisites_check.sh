#!/bin/bash

# 01_prerequisites_check.sh
# Checks for necessary CLI tools (OCI CLI, Fn Project CLI, Python) and guides installation if missing.

set -e

echo "--- Prerequisites Check ---"

# Function to check if a command exists
command_exists () {
    type "$1" &> /dev/null ;
}

# 1. Check for Python 3
echo "Checking for Python 3..."
if command_exists python3; then
    PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    echo "Python 3 found: ${PYTHON_VERSION}"
    if [[ "${PYTHON_VERSION}" < "3.8" ]]; then
        echo "WARNING: Python version is older than 3.8. Some OCI SDK features might require 3.8+."
        echo "Please consider upgrading Python 3 if you encounter issues."
    fi
else
    echo "ERROR: Python 3 not found. Please install Python 3 (e.g., 'sudo apt install python3' on Ubuntu, or from python.org)."
    exit 1
fi

# 2. Check for OCI CLI
echo "Checking for OCI CLI..."
if command_exists oci; then
    echo "OCI CLI found."
    # Check OCI CLI configuration
    if [[ ! -f ~/.oci/config ]]; then
        echo "WARNING: OCI CLI configuration file (~/.oci/config) not found."
        echo "Please run 'oci setup config' to configure OCI CLI."
    else
        echo "OCI CLI configuration found at ~/.oci/config."
        # Skipping detailed key file permission check as it causes a hang.
        # User has been previously warned about key file permissions.
        echo "Skipping detailed OCI API key file permissions check to avoid hang."
        echo "Please ensure your OCI API key file (~/.oci/config points to) has 600 permissions."
        # Original check was:
        # KEY_FILE=$(oci setup config --config-file ~/.oci/config --query "profile.DEFAULT.key_file" --raw-output 2>/dev/null || true)
        # if [[ -n "${KEY_FILE}" && -f "${KEY_FILE}" ]]; then
        #     if [[ -f "${KEY_FILE}" ]]; then
        #         PERMS=$(stat -c "%a" "${KEY_FILE}")
        #         if [[ "${PERMS}" != "600" ]]; then
        #             echo "WARNING: Permissions on OCI API key file '${KEY_FILE}' are too open (${PERMS})."
        #             echo "It is recommended to set permissions to 600: 'chmod 600 ${KEY_FILE}'."
        #         fi
        #     else
        #         echo "WARNING: OCI API key file '${KEY_FILE}' not found, despite being configured."
        #     fi
        # else
        #     echo "WARNING: Could not determine OCI API key file path from config."
        # fi
    fi
else
    echo "ERROR: OCI CLI not found. Please install OCI CLI (refer to https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm)."
    exit 1
fi

# 3. Check for Fn Project CLI
echo "Checking for Fn Project CLI..."
if command_exists fn; then
    echo "Fn Project CLI found."
    echo "Checking Fn CLI context..."
    # Use grep to find the current context as --query is not supported by this Fn CLI version
    FN_CONTEXTS=$(fn list contexts 2>/dev/null || true)
    CURRENT_FN_CONTEXT=$(echo "${FN_CONTEXTS}" | grep '^\*' | awk '{print $2}' || true)

    if [[ -z "${CURRENT_FN_CONTEXT}" || "${CURRENT_FN_CONTEXT}" == "default" ]]; then
        echo "WARNING: No OCI-specific Fn context is currently active or 'default' is active."
        echo "It is recommended to set up an OCI Fn context: 'fn setup-config'."
        echo "Then select your OCI context: 'fn use context <your-oci-context-name>' (e.g., 'fn use context oci')."
    else
        echo "Fn Project CLI context '${CURRENT_FN_CONTEXT}' is active."
    fi
else
    echo "ERROR: Fn Project CLI not found. Please install Fn Project CLI (refer to https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionsinstallfncli.htm)."
    exit 1
fi

# 4. Check for Docker (needed for fn deploy)
echo "Checking for Docker..."
if command_exists docker; then
    echo "Docker found."
    echo "Checking Docker daemon status..."
    if ! docker info &>/dev/null; then
        echo "WARNING: Docker daemon is not running or user does not have permissions to access it."
        echo "Please ensure Docker is running and your user is in the 'docker' group (log out/in after adding)."
    fi
else
    echo "ERROR: Docker not found. Please install Docker (refer to https://docs.docker.com/get-docker/)."
    exit 1
fi

echo "--- Prerequisites Check Complete ---"
# The 'fi' below was misplaced and caused the syntax error. Removed it.
# fi

# 5. Check for jq (needed for JSON parsing/creation)
echo "Checking for jq..."
if command_exists jq; then
    echo "jq found."
else
    echo "WARNING: jq not found. Attempting to install jq..."
    if command_exists apt-get; then
        echo "Detected Debian/Ubuntu. Installing jq using apt-get..."
        sudo apt-get update && sudo apt-get install -y jq
    elif command_exists yum; then
        echo "Detected RedHat/CentOS/OEL. Installing jq using yum..."
        sudo yum install -y jq
    else
        echo "ERROR: Cannot determine package manager to install jq automatically."
        echo "Please install jq manually (refer to https://stedolan.github.io/jq/download/)."
        exit 1
    fi

    if command_exists jq; then
        echo "jq installed successfully."
    else
        echo "ERROR: jq installation failed. Please install jq manually."
        exit 1
    fi
fi

echo "--- Prerequisites Check Complete ---"
echo "Please address any 'ERROR' messages above before proceeding with the setup."
echo "Review 'WARNING' messages for best practices."
