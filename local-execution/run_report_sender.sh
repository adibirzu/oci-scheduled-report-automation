#!/bin/bash

# run_report_sender.sh
# Wrapper script for the OCI Report Sender
# This script sets up the environment and runs the Python report sender

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Set up logging
LOG_FILE="$SCRIPT_DIR/run_report_sender.log"
PYTHON_SCRIPT="$SCRIPT_DIR/send_latest_report.py"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting OCI Report Sender execution"

# Check if Python script exists
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    log_message "ERROR: Python script not found: $PYTHON_SCRIPT"
    exit 1
fi

# Check if config file exists
CONFIG_FILE="$SCRIPT_DIR/../config.env"
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_message "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    log_message "ERROR: Python 3 is not installed or not in PATH"
    exit 1
fi

# Check if required Python packages are installed
log_message "Checking Python dependencies..."
python3 -c "import oci, pathlib, hashlib" 2>/dev/null || {
    log_message "ERROR: Required Python packages not installed. Please install: pip3 install oci-cli"
    exit 1
}

# Set environment variables for OCI CLI if not already set
export OCI_CONFIG_FILE="${OCI_CONFIG_FILE:-$HOME/.oci/config}"
export OCI_CONFIG_PROFILE="${OCI_CONFIG_PROFILE:-DEFAULT}"

# Check if OCI config exists
if [[ ! -f "$OCI_CONFIG_FILE" ]]; then
    log_message "ERROR: OCI config file not found: $OCI_CONFIG_FILE"
    log_message "Please run 'oci setup config' to configure OCI CLI"
    exit 1
fi

log_message "Environment checks passed. Running Python script..."

# Run the Python script and capture output
if python3 "$PYTHON_SCRIPT" 2>&1 | tee -a "$LOG_FILE"; then
    log_message "OCI Report Sender completed successfully"
    exit 0
else
    log_message "OCI Report Sender failed with exit code $?"
    exit 1
fi
