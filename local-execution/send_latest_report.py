#!/usr/bin/env python3
"""
Local Email Sender for OCI Usage Reports
Sends the latest uploaded file from OCI Object Storage bucket via email.
Tracks sent files to avoid duplicates.
"""

import os
import sys
import json
import smtplib
import base64
import logging
import hashlib
from datetime import datetime
from pathlib import Path
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders

import oci
from oci.secrets import SecretsClient
from oci.signer import Signer
from oci.object_storage import ObjectStorageClient

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('send_latest_report.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class ReportSender:
    def __init__(self, config_file='../config.env'):
        """Initialize the report sender with configuration."""
        self.config = self.load_config(config_file)
        self.sent_files_db = 'sent_files.json'
        self.sent_files = self.load_sent_files()
        
        # Initialize OCI clients
        self.oci_config = self.setup_oci_config()
        self.signer = self.setup_signer()
        self.oss_client = ObjectStorageClient(config=self.oci_config, signer=self.signer)
        self.secrets_client = SecretsClient(config=self.oci_config, signer=self.signer)
    
    def load_config(self, config_file):
        """Load configuration from config.env file."""
        config = {}
        config_path = Path(__file__).parent / config_file
        
        if not config_path.exists():
            raise FileNotFoundError(f"Configuration file not found: {config_path}")
        
        with open(config_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # Remove quotes if present
                    value = value.strip('"\'')
                    config[key] = value
        
        # Validate required configuration
        required_keys = [
            'NAMESPACE', 'REPORT_BUCKET_NAME', 'EMAIL_SENDER', 'EMAIL_RECIPIENT',
            'SMTP_USERNAME_SECRET_OCID', 'SMTP_PASSWORD_SECRET_OCID',
            'SMTP_SERVER', 'SMTP_PORT'
        ]
        
        missing_keys = [key for key in required_keys if not config.get(key)]
        if missing_keys:
            raise ValueError(f"Missing required configuration keys: {missing_keys}")
        
        logger.info("Configuration loaded successfully")
        return config
    
    def setup_oci_config(self):
        """Setup OCI configuration."""
        try:
            oci_config_path = os.environ.get("OCI_CONFIG_FILE", os.path.expanduser("~/.oci/config"))
            oci_profile_name = os.environ.get("OCI_CONFIG_PROFILE", "DEFAULT")
            return oci.config.from_file(file_location=oci_config_path, profile_name=oci_profile_name)
        except Exception as e:
            logger.error(f"Failed to setup OCI config: {e}")
            raise
    
    def setup_signer(self):
        """Setup OCI signer."""
        try:
            return Signer(
                tenancy=self.oci_config["tenancy"],
                user=self.oci_config["user"],
                fingerprint=self.oci_config["fingerprint"],
                private_key_file_location=self.oci_config["key_file"],
                pass_phrase=oci.config.get_config_value_or_default(self.oci_config, "pass_phrase")
            )
        except Exception as e:
            logger.error(f"Failed to setup OCI signer: {e}")
            raise
    
    def load_sent_files(self):
        """Load the database of previously sent files."""
        sent_files_path = Path(__file__).parent / self.sent_files_db
        if sent_files_path.exists():
            try:
                with open(sent_files_path, 'r') as f:
                    return json.load(f)
            except Exception as e:
                logger.warning(f"Failed to load sent files database: {e}")
        return {}
    
    def save_sent_files(self):
        """Save the database of sent files."""
        sent_files_path = Path(__file__).parent / self.sent_files_db
        try:
            with open(sent_files_path, 'w') as f:
                json.dump(self.sent_files, f, indent=2, default=str)
            logger.info("Sent files database updated")
        except Exception as e:
            logger.error(f"Failed to save sent files database: {e}")
    
    def get_latest_report_file(self):
        """Get the latest report file from the bucket."""
        try:
            logger.info(f"Searching for latest report in bucket '{self.config['REPORT_BUCKET_NAME']}'")
            
            list_objects_response = self.oss_client.list_objects(
                namespace_name=self.config['NAMESPACE'],
                bucket_name=self.config['REPORT_BUCKET_NAME'],
                prefix="WeeklyCostsScheduledReport_",
                fields="timeCreated,name,size"
            )
            
            if not list_objects_response.data.objects:
                logger.warning("No report files found in bucket")
                return None
            
            # Filter for CSV.GZ files and sort by creation time
            report_files = [
                obj for obj in list_objects_response.data.objects 
                if obj.name.endswith(".csv.gz")
            ]
            
            if not report_files:
                logger.warning("No CSV.GZ report files found")
                return None
            
            # Sort by time created (newest first)
            report_files.sort(key=lambda obj: obj.time_created, reverse=True)
            latest_file = report_files[0]
            
            logger.info(f"Latest report file: {latest_file.name} (created: {latest_file.time_created}, size: {latest_file.size} bytes)")
            return latest_file
            
        except Exception as e:
            logger.error(f"Failed to get latest report file: {e}")
            raise
    
    def is_file_already_sent(self, file_name, file_time_created):
        """Check if a file has already been sent."""
        file_key = f"{file_name}_{file_time_created}"
        file_hash = hashlib.md5(file_key.encode()).hexdigest()
        return file_hash in self.sent_files
    
    def mark_file_as_sent(self, file_name, file_time_created):
        """Mark a file as sent in the database."""
        file_key = f"{file_name}_{file_time_created}"
        file_hash = hashlib.md5(file_key.encode()).hexdigest()
        self.sent_files[file_hash] = {
            'file_name': file_name,
            'time_created': str(file_time_created),
            'sent_at': datetime.now().isoformat()
        }
        self.save_sent_files()
    
    def get_secret(self, secret_ocid):
        """Retrieve a secret from OCI Vault."""
        try:
            secret_bundle = self.secrets_client.get_secret_bundle(secret_id=secret_ocid)
            content = secret_bundle.data.secret_bundle_content.content.encode("utf-8")
            return base64.b64decode(content).decode("utf-8")
        except Exception as e:
            logger.error(f"Failed to retrieve secret {secret_ocid}: {e}")
            raise
    
    def download_file(self, file_name):
        """Download file from OCI Object Storage."""
        try:
            logger.info(f"Downloading file: {file_name}")
            obj = self.oss_client.get_object(
                namespace_name=self.config['NAMESPACE'],
                bucket_name=self.config['REPORT_BUCKET_NAME'],
                object_name=file_name
            )
            return obj.data.content
        except Exception as e:
            logger.error(f"Failed to download file {file_name}: {e}")
            raise
    
    def send_email(self, file_name, file_data):
        """Send email with the report file attached."""
        try:
            logger.info("Retrieving SMTP credentials from vault")
            smtp_username = self.get_secret(self.config['SMTP_USERNAME_SECRET_OCID'])
            smtp_password = self.get_secret(self.config['SMTP_PASSWORD_SECRET_OCID'])
            
            # Create email message
            msg = MIMEMultipart()
            msg["From"] = self.config['EMAIL_SENDER']
            msg["To"] = self.config['EMAIL_RECIPIENT']
            msg["Subject"] = f"OCI Usage Report: {file_name}"
            
            # Email body
            body = f"""
Hello,

Please find attached the latest OCI Usage Report: {file_name}

This report was automatically generated and sent by the OCI Report Automation system.

Report Details:
- File: {file_name}
- Size: {len(file_data):,} bytes
- Sent: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

Best regards,
OCI Report Automation System
            """.strip()
            
            msg.attach(MIMEText(body, "plain"))
            
            # Attach the file
            part = MIMEBase("application", "octet-stream")
            part.set_payload(file_data)
            encoders.encode_base64(part)
            part.add_header("Content-Disposition", f'attachment; filename="{file_name}"')
            msg.attach(part)
            
            # Send email
            logger.info(f"Sending email to {self.config['EMAIL_RECIPIENT']}")
            with smtplib.SMTP(self.config['SMTP_SERVER'], int(self.config['SMTP_PORT'])) as server:
                server.starttls()
                server.login(smtp_username, smtp_password)
                server.send_message(msg)
            
            logger.info("Email sent successfully")
            
        except Exception as e:
            logger.error(f"Failed to send email: {e}")
            raise
    
    def run(self):
        """Main execution method."""
        try:
            logger.info("Starting OCI Report Sender")
            
            # Get latest report file
            latest_file = self.get_latest_report_file()
            if not latest_file:
                logger.info("No report files found. Nothing to send.")
                return
            
            # Check if file was already sent
            if self.is_file_already_sent(latest_file.name, latest_file.time_created):
                logger.info(f"File {latest_file.name} was already sent. Skipping.")
                return
            
            # Download and send the file
            file_data = self.download_file(latest_file.name)
            self.send_email(latest_file.name, file_data)
            
            # Mark file as sent
            self.mark_file_as_sent(latest_file.name, latest_file.time_created)
            
            logger.info(f"Successfully sent report: {latest_file.name}")
            
        except Exception as e:
            logger.error(f"Failed to send report: {e}")
            sys.exit(1)

def main():
    """Main entry point."""
    try:
        sender = ReportSender()
        sender.run()
    except Exception as e:
        logger.error(f"Application failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
