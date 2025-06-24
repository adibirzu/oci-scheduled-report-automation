# OCI Report Automation - Code Logic Documentation

## Function Implementation Overview

The `func.py` file contains the core logic for the OCI Function that processes usage reports and sends them via email. This document provides a detailed breakdown of the code structure, logic flow, and implementation details.

## Code Structure

```python
# Core Imports and Dependencies
import io, json, os, smtplib, base64, logging, sys, traceback
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
```

## Function Architecture

### 1. Logging Configuration
```python
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stdout,
    force=True
)
logger = logging.getLogger(__name__)
```

**Purpose**: Configures comprehensive logging for debugging and monitoring
**Key Features**:
- Outputs to stdout for OCI Functions logging service
- Includes timestamp, logger name, level, and message
- Force=True ensures configuration takes effect in OCI Functions environment

### 2. Helper Functions

#### get_latest_report_filename()
```python
def get_latest_report_filename(oss_client, namespace, bucket_name, prefix="WeeklyCostsScheduledReport_"):
    """Get the latest report filename from Object Storage"""
    # Lists objects with specific prefix
    # Filters for .csv.gz files
    # Sorts by creation time (newest first)
    # Returns latest filename
```

**Logic Flow**:
1. Query Object Storage for objects with specified prefix
2. Filter results to only include `.csv.gz` files
3. Sort by `time_created` in descending order
4. Return the most recent file name

**Error Handling**:
- Logs warnings if no matching files found
- Raises exceptions for Object Storage API errors
- Returns None if no valid files exist

#### get_secret()
```python
def get_secret(secret_id, signer, config_for_client=None):
    """Fetch secret from OCI Vault"""
    # Creates Secrets client with authentication
    # Retrieves secret bundle
    # Decodes base64 content
    # Returns plaintext secret value
```

**Logic Flow**:
1. Initialize SecretsClient with provided signer
2. Call `get_secret_bundle()` with secret OCID
3. Extract base64-encoded content from response
4. Decode base64 to get plaintext value

**Security Features**:
- Uses Resource Principal authentication
- Logs secret retrieval without exposing values
- Handles authentication errors gracefully

### 3. Main Handler Function

#### handler()
```python
def handler(ctx, data: io.BytesIO = None):
    """Main function handler"""
```

The main handler follows a structured execution flow with comprehensive error handling and logging.

## Detailed Logic Flow

### Phase 1: Initialization and Input Parsing

```python
logger.info("=== OCI Function Handler Started ===")

# Parse input data
body = {}
if data:
    try:
        body = json.loads(data.getvalue())
        logger.info(f"Parsed body keys: {list(body.keys())}")
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse JSON data: {str(e)}")
        body = {}
```

**Logic**:
1. Log function start for debugging
2. Attempt to parse JSON payload from event
3. Handle JSON parsing errors gracefully
4. Log available keys for debugging

**Error Handling**:
- Catches `json.JSONDecodeError` for malformed input
- Continues execution with empty body if parsing fails
- Logs detailed error information

### Phase 2: Object Name Extraction

```python
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
    object_name = "test-report.csv"
```

**Logic**:
1. Check standard OCI Events payload structure (`data.resourceName`)
2. Check alternative payload structure (`objectName`)
3. Fall back to test mode if no object name found
4. Log the source and value of object name

**Flexibility**:
- Supports multiple payload formats
- Graceful degradation for testing scenarios
- Clear logging of data source

### Phase 3: Authentication Setup

```python
# Initialize OCI authentication
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
    except Exception as e:
        logger.error(f"Failed to initialize local OCI authentication: {str(e)}")
        raise
```

**Logic**:
1. Check for Resource Principal environment variable
2. Use Resource Principal if available (production)
3. Fall back to local OCI config for development/testing
4. Create appropriate signer for OCI API calls

**Authentication Methods**:
- **Resource Principal**: Automatic authentication in OCI Functions
- **Local Config**: File-based authentication for development
- **Error Handling**: Detailed logging and exception propagation

### Phase 4: Environment Validation

```python
# Get environment variables
env_vars = {
    "SMTP_USERNAME_SECRET_OCID": os.environ.get("SMTP_USERNAME_SECRET_OCID"),
    "SMTP_PASSWORD_SECRET_OCID": os.environ.get("SMTP_PASSWORD_SECRET_OCID"),
    "EMAIL_FROM": os.environ.get("EMAIL_FROM"),
    "EMAIL_TO": os.environ.get("EMAIL_TO"),
    "SMTP_SERVER": os.environ.get("SMTP_SERVER", "smtp.email.your-region.oci.oraclecloud.com"),
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
```

**Logic**:
1. Extract all required environment variables
2. Provide defaults for optional variables (SMTP server/port)
3. Log variable status without exposing sensitive values
4. Validate all required variables are present
5. Raise detailed error if any required variables missing

**Security Features**:
- Masks secret OCIDs in logs (shows only SET/NOT SET)
- Logs non-sensitive configuration for debugging
- Fails fast if critical configuration missing

### Phase 5: File Download

```python
# Initialize Object Storage client
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
```

**Logic**:
1. Create Object Storage client with authentication
2. Attempt to download specified file
3. Extract file content as bytes
4. Log success with file size information

**Error Handling**:
- Catches all exceptions during file download
- Logs detailed error information
- Re-raises exception to halt execution

### Phase 6: Secret Retrieval

```python
# Get SMTP credentials from vault
logger.info("Retrieving SMTP credentials from vault...")
try:
    smtp_user = get_secret(env_vars["SMTP_USERNAME_SECRET_OCID"], signer, config_for_clients)
    smtp_pass = get_secret(env_vars["SMTP_PASSWORD_SECRET_OCID"], signer, config_for_clients)
    logger.info("SMTP credentials retrieved successfully")
except Exception as e:
    logger.error(f"Failed to retrieve SMTP credentials: {str(e)}")
    raise
```

**Logic**:
1. Call helper function to retrieve username secret
2. Call helper function to retrieve password secret
3. Log success without exposing credential values

**Security Features**:
- Uses helper function for consistent secret handling
- No credential values logged
- Proper exception handling and re-raising

### Phase 7: Email Composition

```python
# Prepare email
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
part = MIMEBase("application", "octet-stream")
part.set_payload(file_data)
encoders.encode_base64(part)
part.add_header("Content-Disposition", f'attachment; filename="{object_name}"')
msg.attach(part)
```

**Logic**:
1. Create multipart MIME message
2. Set email headers (From, To, Subject)
3. Create professional email body with report details
4. Attach file as base64-encoded binary attachment
5. Set proper content disposition for attachment

**Email Features**:
- Professional email formatting
- Dynamic subject line with file name
- Proper MIME structure for attachments
- Base64 encoding for binary files

### Phase 8: Email Delivery

```python
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
```

**Logic**:
1. Connect to SMTP server
2. Start TLS encryption
3. Authenticate with retrieved credentials
4. Send composed message
5. Close connection cleanly

**Security Features**:
- TLS encryption for email transmission
- Secure credential handling
- Proper connection cleanup

### Phase 9: Response Generation

```python
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
```

**Logic**:
1. Create structured success response
2. Include relevant execution details
3. Log successful completion
4. Return appropriate response format (FDK vs local)

**Response Features**:
- Structured JSON response
- Includes execution metadata
- Different handling for function vs local execution

## Error Handling Strategy

### Global Exception Handling

```python
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
```

**Features**:
- Catches all unhandled exceptions
- Logs full stack trace for debugging
- Returns structured error response
- Includes error type for categorization
- Different behavior for function vs local execution

### Error Categories

1. **Parse Errors**: Malformed input JSON
2. **Authentication Errors**: OCI authentication failures
3. **Configuration Errors**: Missing environment variables
4. **Storage Errors**: Object Storage access failures
5. **Vault Errors**: Secret retrieval failures
6. **SMTP Errors**: Email delivery failures

## Testing and Development Support

### Local Testing Support

```python
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
```

**Features**:
- Enables local function testing
- Simulates OCI Events payload
- Provides test output formatting

### Development vs Production Behavior

| Aspect | Development | Production |
|--------|-------------|------------|
| Authentication | Local OCI config | Resource Principal |
| Logging | Console output | OCI Logging Service |
| Error Handling | Raises exceptions | Returns error responses |
| Configuration | Environment variables | Function config |

## Performance Considerations

### Memory Optimization
- Streams file content directly without intermediate storage
- Uses efficient MIME encoding for attachments
- Minimal object creation in hot paths

### Execution Time Optimization
- Resource Principal authentication (no credential lookup)
- Single Object Storage API call
- Efficient secret retrieval
- Direct SMTP connection

### Scalability Features
- Stateless function design
- No persistent connections
- Minimal memory footprint
- Fast cold start capability

## Security Implementation

### Credential Management
- No hardcoded credentials
- Vault-based secret storage
- Resource Principal authentication
- Secure credential transmission

### Data Protection
- TLS encryption for email
- Secure secret retrieval
- No sensitive data logging
- Proper error message sanitization

### Access Control
- Least privilege IAM policies
- Dynamic group-based access
- Compartment-scoped permissions
- Resource-specific access rules

This code implementation provides a robust, secure, and scalable solution for automated OCI usage report processing and delivery.
