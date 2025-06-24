import io
import json
import os
import smtplib
import base64
import logging
import sys
import traceback

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders

from fdk import response

import oci
from oci.secrets import SecretsClient
from oci.auth.signers import get_resource_principals_signer
from oci.signer import Signer
from oci.object_storage import ObjectStorageClient

# Configure logging for OCI Functions
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stdout,
    force=True
)
logger = logging.getLogger(__name__)

def get_latest_report_filename(oss_client, namespace, bucket_name, prefix="WeeklyCostsScheduledReport_"):
    """Get the latest report filename from Object Storage"""
    logger.info(f"Listing objects in bucket '{bucket_name}' with prefix '{prefix}'...")
    latest_file = None
    latest_time_created = None

    try:
        list_objects_response = oss_client.list_objects(
            namespace_name=namespace,
            bucket_name=bucket_name,
            prefix=prefix,
            fields="timeCreated,name"
        )
        
        if list_objects_response.data.objects:
            report_files = [
                obj for obj in list_objects_response.data.objects 
                if obj.name.endswith(".csv.gz")
            ]
            
            if not report_files:
                logger.warning(f"No files matching '{prefix}*.csv.gz' found in bucket '{bucket_name}'.")
                return None

            report_files.sort(key=lambda obj: obj.time_created, reverse=True)
            
            latest_file_obj = report_files[0]
            latest_file = latest_file_obj.name
            latest_time_created = latest_file_obj.time_created
            logger.info(f"Latest report file found: '{latest_file}' (created at {latest_time_created}).")
        else:
            logger.warning(f"No objects found with prefix '{prefix}' in bucket '{bucket_name}'.")
            
    except Exception as e:
        logger.error(f"Error listing objects in bucket '{bucket_name}': {str(e)}")
        raise
    
    return latest_file

def get_secret(secret_id, signer, config_for_client=None):
    """Fetch secret from OCI Vault"""
    try:
        logger.info(f"Fetching secret: {secret_id}")
        client = SecretsClient(config=config_for_client if config_for_client else {}, signer=signer)
        secret_bundle = client.get_secret_bundle(secret_id=secret_id)
        content = secret_bundle.data.secret_bundle_content.content.encode("utf-8")
        decoded_content = base64.b64decode(content).decode("utf-8")
        logger.info("Secret retrieved successfully")
        return decoded_content
    except Exception as e:
        logger.error(f"Error fetching secret {secret_id}: {str(e)}")
        raise

def handler(ctx, data: io.BytesIO = None):
    """Main function handler"""
    logger.info("=== OCI Function Handler Started ===")
    
    try:
        # Parse input data
        logger.info("Parsing input data...")
        body = {}
        if data:
            try:
                body = json.loads(data.getvalue())
                logger.info(f"Parsed body keys: {list(body.keys())}")
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse JSON data: {str(e)}")
                body = {}
        
        # Extract object name from event payload
        object_name = None
        if "data" in body and "resourceName" in body["data"]:
            object_name = body["data"]["resourceName"]
            logger.info(f"Object name from event: {object_name}")
        elif "objectName" in body:
            object_name = body["objectName"]
            logger.info(f"Object name from direct payload: {object_name}")
        else:
            logger.warning("No object name found in payload, using test mode")
            # For testing purposes, we can proceed without an object name
            # In production, this would be an error
            object_name = "test-report.csv"
        
        logger.info(f"Processing object: {object_name}")
        
        # Initialize OCI authentication
        logger.info("Initializing OCI authentication...")
        config_for_clients = {}
        
        if "OCI_RESOURCE_PRINCIPAL_VERSION" in os.environ:
            logger.info("Using Resource Principal authentication")
            signer = get_resource_principals_signer()
        else:
            logger.info("Using local OCI config authentication")
            try:
                oci_config_path = os.environ.get("OCI_CONFIG_FILE", os.path.expanduser("~/.oci/config"))
                oci_profile_name = os.environ.get("OCI_CONFIG_PROFILE", "DEFAULT")
                config_for_clients = oci.config.from_file(file_location=oci_config_path, profile_name=oci_profile_name)
                
                signer = Signer(
                    tenancy=config_for_clients["tenancy"],
                    user=config_for_clients["user"],
                    fingerprint=config_for_clients["fingerprint"],
                    private_key_file_location=config_for_clients["key_file"],
                    pass_phrase=oci.config.get_config_value_or_default(config_for_clients, "pass_phrase")
                )
                logger.info(f"Using local OCI config from: {oci_config_path}")
            except Exception as e:
                logger.error(f"Failed to initialize local OCI authentication: {str(e)}")
                raise
        
        # Get environment variables
        logger.info("Checking environment variables...")
        env_vars = {
            "SMTP_USERNAME_SECRET_OCID": os.environ.get("SMTP_USERNAME_SECRET_OCID"),
            "SMTP_PASSWORD_SECRET_OCID": os.environ.get("SMTP_PASSWORD_SECRET_OCID"),
            "EMAIL_FROM": os.environ.get("EMAIL_FROM"),
            "EMAIL_TO": os.environ.get("EMAIL_TO"),
            "SMTP_SERVER": os.environ.get("SMTP_SERVER", "smtp.email.eu-frankfurt-1.oci.oraclecloud.com"),
            "SMTP_PORT": os.environ.get("SMTP_PORT", "587"),
            "NAMESPACE": os.environ.get("NAMESPACE"),
            "BUCKET_NAME": os.environ.get("BUCKET_NAME")
        }
        
        # Log environment variables (safely)
        for key, value in env_vars.items():
            if "SECRET" in key:
                logger.info(f"Environment variable {key}: {'SET' if value else 'NOT SET'}")
            else:
                logger.info(f"Environment variable {key}: {value}")
        
        # Check for required environment variables
        required_vars = ["SMTP_USERNAME_SECRET_OCID", "SMTP_PASSWORD_SECRET_OCID", 
                        "EMAIL_FROM", "EMAIL_TO", "NAMESPACE", "BUCKET_NAME"]
        missing_vars = [var for var in required_vars if not env_vars[var]]
        
        if missing_vars:
            error_msg = f"Missing required environment variables: {', '.join(missing_vars)}"
            logger.error(error_msg)
            raise ValueError(error_msg)
        
        logger.info("All required environment variables are present")
        
        # Initialize Object Storage client
        logger.info("Initializing Object Storage client...")
        oss_client = ObjectStorageClient(config=config_for_clients, signer=signer)
        
        # Get file from Object Storage
        namespace = env_vars["NAMESPACE"]
        bucket_name = env_vars["BUCKET_NAME"]
        
        logger.info(f"Fetching object '{object_name}' from namespace '{namespace}', bucket '{bucket_name}'...")
        try:
            obj = oss_client.get_object(namespace, bucket_name, object_name)
            file_data = obj.data.content
            logger.info(f"Object '{object_name}' fetched successfully, size: {len(file_data)} bytes")
        except Exception as e:
            logger.error(f"Failed to fetch object '{object_name}': {str(e)}")
            raise
        
        # Get SMTP credentials from vault
        logger.info("Retrieving SMTP credentials from vault...")
        try:
            smtp_user = get_secret(env_vars["SMTP_USERNAME_SECRET_OCID"], signer, config_for_clients)
            smtp_pass = get_secret(env_vars["SMTP_PASSWORD_SECRET_OCID"], signer, config_for_clients)
            logger.info("SMTP credentials retrieved successfully")
        except Exception as e:
            logger.error(f"Failed to retrieve SMTP credentials: {str(e)}")
            raise
        
        # Prepare email
        logger.info("Preparing email...")
        msg = MIMEMultipart()
        msg["From"] = env_vars["EMAIL_FROM"]
        msg["To"] = env_vars["EMAIL_TO"]
        msg["Subject"] = f"OCI Usage Report: {object_name}"
        
        # Add email body
        email_body = f"""
Hello,

Please find attached the OCI Usage Report: {object_name}

This report was automatically generated and sent by the OCI Functions service.

Best regards,
OCI Report Automation
"""
        msg.attach(MIMEText(email_body, "plain"))
        
        # Attach the file
        logger.info(f"Attaching file '{object_name}' to email...")
        part = MIMEBase("application", "octet-stream")
        part.set_payload(file_data)
        encoders.encode_base64(part)
        part.add_header("Content-Disposition", f'attachment; filename="{object_name}"')
        msg.attach(part)
        
        logger.info(f"Email prepared: From: {msg['From']}, To: {msg['To']}, Subject: {msg['Subject']}")
        
        # Send email
        logger.info(f"Connecting to SMTP server {env_vars['SMTP_SERVER']}:{env_vars['SMTP_PORT']}...")
        try:
            server = smtplib.SMTP(env_vars["SMTP_SERVER"], int(env_vars["SMTP_PORT"]))
            server.starttls()
            server.login(smtp_user, smtp_pass)
            server.send_message(msg)
            server.quit()
            logger.info("Email sent successfully!")
        except Exception as e:
            logger.error(f"Failed to send email: {str(e)}")
            raise
        
        # Return success response
        result = {
            "status": "success",
            "message": f"Email sent successfully for {object_name}",
            "object_name": object_name,
            "recipient": env_vars["EMAIL_TO"]
        }
        
        logger.info("Function execution completed successfully")
        
        if ctx:
            return response.Response(ctx, response_data=json.dumps(result), status_code=200)
        else:
            print("Local Test Result:", json.dumps(result, indent=2))
            return result
            
    except Exception as e:
        error_msg = f"Function execution failed: {str(e)}"
        logger.error(error_msg)
        logger.error(f"Full traceback: {traceback.format_exc()}")
        
        result = {
            "status": "error",
            "message": error_msg,
            "error_type": type(e).__name__
        }
        
        if ctx:
            return response.Response(ctx, response_data=json.dumps(result), status_code=500)
        else:
            print("Local Test Error:", json.dumps(result, indent=2))
            raise

# For local testing
if __name__ == "__main__":
    # Test the function locally
    test_data = {
        "data": {
            "resourceName": "test-report.csv"
        }
    }
    
    test_data_bytes = io.BytesIO(json.dumps(test_data).encode())
    result = handler(None, test_data_bytes)
    print("Test completed:", result)
