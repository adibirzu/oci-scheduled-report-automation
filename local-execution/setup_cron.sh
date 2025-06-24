#!/bin/bash

# setup_cron.sh
# Sets up a cron job to run the OCI Report Sender daily

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_SCRIPT="$SCRIPT_DIR/run_report_sender.sh"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --time HH:MM    Set the time to run daily (default: 09:00)"
    echo "  --install       Install the cron job"
    echo "  --uninstall     Remove the cron job"
    echo "  --status        Show current cron job status"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --install                    # Install with default time (09:00)"
    echo "  $0 --install --time 14:30       # Install to run daily at 14:30"
    echo "  $0 --status                     # Check if cron job is installed"
    echo "  $0 --uninstall                  # Remove the cron job"
}

# Default values
RUN_TIME="09:00"
ACTION=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --time)
            RUN_TIME="$2"
            shift 2
            ;;
        --install)
            ACTION="install"
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate time format
if [[ ! "$RUN_TIME" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
    echo "ERROR: Invalid time format. Use HH:MM (24-hour format)"
    exit 1
fi

# Extract hour and minute
HOUR=$(echo "$RUN_TIME" | cut -d: -f1)
MINUTE=$(echo "$RUN_TIME" | cut -d: -f2)

# Remove leading zeros to avoid octal interpretation
HOUR=$((10#$HOUR))
MINUTE=$((10#$MINUTE))

# Validate hour and minute ranges
if [[ $HOUR -gt 23 ]] || [[ $MINUTE -gt 59 ]]; then
    echo "ERROR: Invalid time. Hour must be 00-23, minute must be 00-59"
    exit 1
fi

# Cron job identifier comment
CRON_COMMENT="# OCI Report Sender - Auto-generated"
CRON_JOB="$MINUTE $HOUR * * * $WRAPPER_SCRIPT >/dev/null 2>&1 $CRON_COMMENT"

# Function to check if cron job exists
cron_job_exists() {
    crontab -l 2>/dev/null | grep -q "OCI Report Sender - Auto-generated"
}

# Function to install cron job
install_cron_job() {
    echo "Installing cron job to run daily at $RUN_TIME..."
    
    # Check if wrapper script exists and is executable
    if [[ ! -f "$WRAPPER_SCRIPT" ]]; then
        echo "ERROR: Wrapper script not found: $WRAPPER_SCRIPT"
        exit 1
    fi
    
    if [[ ! -x "$WRAPPER_SCRIPT" ]]; then
        echo "Making wrapper script executable..."
        chmod +x "$WRAPPER_SCRIPT"
    fi
    
    # Check if cron job already exists
    if cron_job_exists; then
        echo "Cron job already exists. Removing old one first..."
        uninstall_cron_job
    fi
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    
    echo "✅ Cron job installed successfully!"
    echo "   Schedule: Daily at $RUN_TIME"
    echo "   Command: $WRAPPER_SCRIPT"
    echo ""
    echo "The script will:"
    echo "   - Check for the latest report file in the OCI bucket"
    echo "   - Send email only if the file hasn't been sent before"
    echo "   - Log all activities to: $SCRIPT_DIR/run_report_sender.log"
    echo ""
    echo "To check logs: tail -f $SCRIPT_DIR/run_report_sender.log"
}

# Function to uninstall cron job
uninstall_cron_job() {
    if cron_job_exists; then
        echo "Removing OCI Report Sender cron job..."
        crontab -l 2>/dev/null | grep -v "OCI Report Sender - Auto-generated" | crontab -
        echo "✅ Cron job removed successfully!"
    else
        echo "No OCI Report Sender cron job found."
    fi
}

# Function to show cron job status
show_status() {
    echo "=== OCI Report Sender Cron Job Status ==="
    echo ""
    
    if cron_job_exists; then
        echo "✅ Cron job is INSTALLED"
        echo ""
        echo "Current cron job:"
        crontab -l 2>/dev/null | grep -A1 -B1 "OCI Report Sender - Auto-generated" || true
        echo ""
        
        # Show recent log entries if log file exists
        LOG_FILE="$SCRIPT_DIR/run_report_sender.log"
        if [[ -f "$LOG_FILE" ]]; then
            echo "Recent log entries (last 10 lines):"
            echo "---"
            tail -n 10 "$LOG_FILE" 2>/dev/null || echo "No log entries found"
        else
            echo "No log file found yet: $LOG_FILE"
        fi
    else
        echo "❌ Cron job is NOT installed"
        echo ""
        echo "To install: $0 --install"
    fi
    
    echo ""
    echo "Files:"
    echo "  Script: $WRAPPER_SCRIPT"
    echo "  Python: $SCRIPT_DIR/send_latest_report.py"
    echo "  Config: $SCRIPT_DIR/../config.env"
    echo "  Logs: $SCRIPT_DIR/run_report_sender.log"
    echo "  Sent files DB: $SCRIPT_DIR/sent_files.json"
}

# Main execution
case "$ACTION" in
    install)
        install_cron_job
        ;;
    uninstall)
        uninstall_cron_job
        ;;
    status)
        show_status
        ;;
    *)
        echo "ERROR: No action specified"
        echo ""
        usage
        exit 1
        ;;
esac
