# OCI Report Sender - Local Execution

This folder contains scripts for local execution of the OCI Report Sender, which automatically sends the latest usage report files from your OCI Object Storage bucket via email.

## Overview

The local execution system provides:
- **Automated email sending** of the latest report files
- **Duplicate prevention** - tracks sent files to avoid sending the same file multiple times
- **Cron job integration** for daily automated execution
- **Comprehensive logging** for monitoring and troubleshooting
- **Error handling** and recovery mechanisms

## Files

- **`send_latest_report.py`** - Main Python script that handles report detection and email sending
- **`run_report_sender.sh`** - Shell wrapper script with environment checks and logging
- **`setup_cron.sh`** - Cron job management script for automated daily execution
- **`requirements.txt`** - Python dependencies
- **`README.md`** - This documentation file

## Prerequisites

1. **Python 3.8+** installed
2. **OCI CLI** configured with valid credentials
3. **OCI Python SDK** installed
4. **Access to the parent config.env** file with all required settings

## Quick Start

### 1. Install Dependencies

```bash
cd local-execution
pip3 install -r requirements.txt
```

### 2. Make Scripts Executable

```bash
chmod +x *.sh
```

### 3. Test Manual Execution

```bash
./run_report_sender.sh
```

### 4. Set Up Daily Cron Job

```bash
# Install cron job to run daily at 9:00 AM
./setup_cron.sh --install

# Or specify a custom time (e.g., 2:30 PM)
./setup_cron.sh --install --time 14:30
```

## Configuration

The scripts use the parent `config.env` file located at `../config.env`. Ensure the following variables are properly configured:

### Required Variables:
- `NAMESPACE` - OCI Object Storage namespace
- `REPORT_BUCKET_NAME` - Bucket containing usage reports
- `EMAIL_SENDER` - Sender email address
- `EMAIL_RECIPIENT` - Recipient email address
- `SMTP_USERNAME_SECRET_OCID` - Vault secret for SMTP username
- `SMTP_PASSWORD_SECRET_OCID` - Vault secret for SMTP password
- `SMTP_SERVER` - SMTP server hostname
- `SMTP_PORT` - SMTP server port

## How It Works

### 1. Report Detection
- Searches for files with prefix `WeeklyCostsScheduledReport_`
- Filters for `.csv.gz` files
- Selects the most recently created file

### 2. Duplicate Prevention
- Maintains a local database (`sent_files.json`) of previously sent files
- Uses file name + creation timestamp to create unique identifiers
- Skips sending if file was already sent

### 3. Email Sending
- Downloads the latest report file from OCI Object Storage
- Retrieves SMTP credentials from OCI Vault
- Sends email with report attached
- Marks file as sent in the database

### 4. Logging
- All activities logged to `send_latest_report.log` and `run_report_sender.log`
- Includes timestamps, file details, and error information
- Logs are rotated automatically by the system

## Cron Job Management

### Install Cron Job
```bash
# Default time (9:00 AM daily)
./setup_cron.sh --install

# Custom time (e.g., 6:30 PM daily)
./setup_cron.sh --install --time 18:30
```

### Check Status
```bash
./setup_cron.sh --status
```

### Remove Cron Job
```bash
./setup_cron.sh --uninstall
```

## Manual Execution

### Run Once
```bash
./run_report_sender.sh
```

### Run Python Script Directly
```bash
python3 send_latest_report.py
```

## Monitoring

### Check Logs
```bash
# Real-time log monitoring
tail -f send_latest_report.log

# View recent entries
tail -n 50 send_latest_report.log

# Check wrapper script logs
tail -f run_report_sender.log
```

### Check Sent Files Database
```bash
# View sent files history
cat sent_files.json | python3 -m json.tool
```

### Verify Cron Job
```bash
# Check if cron job is running
./setup_cron.sh --status

# View system cron logs (Ubuntu/Debian)
sudo tail -f /var/log/syslog | grep CRON
```

## Troubleshooting

### Common Issues

#### 1. "Configuration file not found"
- Ensure `../config.env` exists and is properly configured
- Check file permissions

#### 2. "OCI config file not found"
- Run `oci setup config` to configure OCI CLI
- Verify `~/.oci/config` exists

#### 3. "Failed to retrieve secret"
- Check that vault secret OCIDs are correct in config.env
- Verify OCI user has permission to read secrets
- Ensure vault and secrets are in the correct region

#### 4. "No report files found"
- Verify bucket name and namespace in config.env
- Check that reports are being generated in OCI
- Ensure OCI user has permission to read the bucket

#### 5. "SMTP authentication failed"
- Verify SMTP credentials in vault secrets
- Check SMTP server and port settings
- Ensure email sender is approved in OCI Email Delivery

### Debug Mode

Enable verbose logging by modifying the Python script:
```python
# Change logging level in send_latest_report.py
logging.basicConfig(level=logging.DEBUG, ...)
```

### Test Components Individually

#### Test OCI Connection
```python
python3 -c "
import oci
config = oci.config.from_file()
print('OCI config loaded successfully')
"
```

#### Test Vault Access
```python
python3 -c "
import oci
from oci.secrets import SecretsClient
config = oci.config.from_file()
client = SecretsClient(config)
print('Vault client created successfully')
"
```

## File Structure

```
local-execution/
├── send_latest_report.py      # Main Python script
├── run_report_sender.sh       # Shell wrapper
├── setup_cron.sh             # Cron management
├── requirements.txt          # Python dependencies
├── README.md                 # This file
├── send_latest_report.log    # Python script logs (created at runtime)
├── run_report_sender.log     # Wrapper script logs (created at runtime)
└── sent_files.json          # Sent files database (created at runtime)
```

## Security Considerations

1. **Credentials**: SMTP credentials are stored securely in OCI Vault
2. **File Permissions**: Ensure log files and database have appropriate permissions
3. **OCI Access**: Uses existing OCI CLI configuration and permissions
4. **Local Storage**: Sent files database contains only metadata, not actual file content

## Maintenance

### Log Rotation
Consider setting up log rotation for the log files:
```bash
# Add to /etc/logrotate.d/oci-report-sender
/path/to/local-execution/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
}
```

### Database Cleanup
The `sent_files.json` database grows over time. You can periodically clean old entries:
```bash
# Backup and clean entries older than 90 days (manual process)
cp sent_files.json sent_files.json.backup
# Edit sent_files.json to remove old entries
```

## Support

For issues or questions:
1. Check the logs for detailed error messages
2. Verify all prerequisites are met
3. Test individual components as described in troubleshooting
4. Ensure OCI permissions are correctly configured
