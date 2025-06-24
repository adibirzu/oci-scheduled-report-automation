# OCI Report Automation

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OCI Functions](https://img.shields.io/badge/OCI-Functions-orange.svg)](https://docs.oracle.com/en-us/iaas/Content/Functions/Concepts/functionsoverview.htm)
[![Python 3.11](https://img.shields.io/badge/python-3.11-blue.svg)](https://www.python.org/downloads/)

A serverless, event-driven solution that automatically processes and emails OCI usage reports when they are uploaded to Object Storage. Built using OCI Functions, Resource Principal authentication, and integrated with multiple OCI services.

## 🏗️ Architecture Overview

The system creates a complete serverless automation pipeline:
- **Object Storage** bucket for usage reports
- **OCI Function** to process and email reports  
- **Event Rule** to trigger function on new report uploads
- **Vault** secrets for secure SMTP credentials
- **IAM policies** for function permissions
- **Resource Principal** authentication for secure access

![Architecture Diagram](ARCHITECTURE.md#architecture-diagram)

## 🚀 Quick Start

### Prerequisites

Ensure you have the following tools installed and configured:

- **OCI CLI** - [Installation Guide](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- **Fn Project CLI** - [Installation Guide](https://fnproject.io/tutorials/install/)
- **Docker** - [Installation Guide](https://docs.docker.com/get-docker/)
- **Python 3.8+** - [Download](https://www.python.org/downloads/)
- **jq** - JSON processor for shell scripts

### 1. Clone and Setup

```bash
git clone <repository-url>
cd oci-report-automation
chmod +x *.sh
```

### 2. Interactive Setup

Run the main setup script for guided configuration:

```bash
./main_setup.sh
```

The script will:
- ✅ Check prerequisites
- ✅ Guide you through configuration
- ✅ Create all required OCI resources
- ✅ Deploy the function
- ✅ Set up IAM policies
- ✅ Test the complete workflow

### 3. Manual Configuration (Alternative)

If you prefer manual configuration, edit `config.env` with your values:

```bash
# Required values
COMPARTMENT_OCID="ocid1.compartment.oc1..aaaa..."
EMAIL_SENDER="sender@example.com"
EMAIL_RECIPIENT="recipient@example.com"
NAMESPACE="your-namespace"
REGION="your-region"

# Optional (will be created if not provided)
VAULT_OCID=""
SMTP_USERNAME_SECRET_OCID=""
SMTP_PASSWORD_SECRET_OCID=""
```

Then run individual setup scripts:

```bash
./01_prerequisites_check.sh
./02_bucket_setup.sh
./03_vault_secrets_setup.sh
./04_email_delivery_setup.sh
./05_function_deploy.sh
./07_setup_iam_policies.sh
./08_create_event_rule.sh  # Optional
./06_test_send.sh
```

## 📋 Setup Process

The automation follows a structured setup process:

### 1. Prerequisites Check (`01_prerequisites_check.sh`)
- Verifies required tools are installed
- Checks OCI CLI configuration
- Validates Docker and Fn CLI setup

### 2. Bucket Setup (`02_bucket_setup.sh`)
- Creates Object Storage bucket for usage reports
- Enables bucket events for function triggering
- Configures proper bucket policies

### 3. Vault Secrets Setup (`03_vault_secrets_setup.sh`)
- Creates new vault and secrets OR uses existing ones
- Stores SMTP credentials securely in OCI Vault
- Handles encryption key management

### 4. Email Delivery Setup (`04_email_delivery_setup.sh`)
- Confirms approved sender configuration
- Validates email delivery service setup
- Tests SMTP connectivity

### 5. Function Deployment (`05_function_deploy.sh`)
- Creates Functions application
- Deploys the function with configuration
- Sets up function logging

### 6. IAM Policies Setup (`07_setup_iam_policies.sh`)
- Creates Dynamic Group for function Resource Principal
- Sets up IAM policies for required permissions
- Validates function access to resources

### 7. Event Rule Setup (`08_create_event_rule.sh`) - Optional
- Creates Event Rule to trigger function on file uploads
- Asks user preference for automatic or manual creation
- Provides detailed manual setup instructions

### 8. Testing (`06_test_send.sh`)
- Tests function locally
- Tests deployed function
- Validates complete workflow

## 🔧 Configuration

### Required Configuration

| Variable | Description | Example |
|----------|-------------|---------|
| `COMPARTMENT_OCID` | Target compartment for resources | `ocid1.compartment.oc1..aaaa...` |
| `EMAIL_SENDER` | Approved sender email address | `sender@example.com` |
| `EMAIL_RECIPIENT` | Recipient email address | `recipient@example.com` |
| `NAMESPACE` | Object Storage namespace | `your-namespace` |
| `REGION` | OCI region | `us-phoenix-1` |

### Optional Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `REPORT_BUCKET_NAME` | Object Storage bucket name | `monthly-usage-reports` |
| `FUNCTION_APP_NAME` | Function application name | `usagereports` |
| `SMTP_SERVER` | SMTP server hostname | `smtp.email.{region}.oci.oraclecloud.com` |
| `SMTP_PORT` | SMTP port | `587` |

### Auto-Generated Values

The following values are automatically generated during setup:

- `VAULT_OCID` - Created vault OCID
- `MASTER_KEY_OCID` - Encryption key OCID  
- `SMTP_USERNAME_SECRET_OCID` - Username secret OCID
- `SMTP_PASSWORD_SECRET_OCID` - Password secret OCID
- `FUNCTION_APP_OCID` - Function application OCID
- `FUNCTION_OCID` - Deployed function OCID
- `DYNAMIC_GROUP_OCID` - IAM dynamic group OCID
- `POLICY_OCID` - IAM policy OCID
- `EVENT_RULE_OCID` - Event rule OCID

## 🔐 Security Features

### Resource Principal Authentication
- **No hardcoded credentials** in function code
- **Automatic credential management** through OCI IAM
- **Least privilege access** - only necessary permissions granted
- **Audit trail** - all access logged through IAM policies

### Secure Credential Storage
- SMTP credentials stored securely in **OCI Vault**
- Function retrieves credentials at runtime using Resource Principal
- **Base64 encoded secrets** for additional security layer
- **Encryption at rest** with customer-managed keys

### IAM Security Model
- **Dynamic Groups** for function resource identification
- **Compartment-scoped policies** for resource access
- **Resource-specific permissions** (bucket, vault, namespace)
- **Automatic policy validation** during setup

## 📊 Monitoring and Logging

### Function Logging
- **Comprehensive logging** enabled by default
- **Structured log messages** with timestamps
- **Error tracking** with full stack traces
- **Performance metrics** for execution time and memory usage

### OCI Logging Integration
- **Automatic log forwarding** to OCI Logging service
- **Centralized log management** across all function executions
- **Log retention policies** configurable per requirements
- **Real-time log streaming** for debugging

### Monitoring Capabilities
- **Function invocation metrics** in OCI Console
- **Error rate tracking** and alerting
- **Performance monitoring** with execution duration
- **Email delivery success rates**

## 🔄 Local Execution Alternative

For environments where you prefer local execution over serverless functions:

```bash
cd local-execution
pip3 install -r requirements.txt
chmod +x *.sh

# Test manual execution
./run_report_sender.sh

# Set up daily cron job
./setup_cron.sh --install
```

See [local-execution/README.md](local-execution/README.md) for detailed documentation.

## 🛠️ Troubleshooting

### Common Issues

#### Configuration Issues
```bash
# Validate configuration
./load_config.sh --validate

# Interactive configuration setup
./load_config.sh --setup
```

#### Function Deployment Issues
- Ensure all prerequisites are met
- Check that the subnet has internet access (NAT Gateway or Service Gateway)
- Verify IAM policies are correctly applied

#### Function Runtime Issues
- Check function logs in OCI Console: **Developer Services > Functions > [App] > [Function] > Logs**
- Verify vault secrets are accessible
- Ensure email delivery is properly configured

#### Permission Issues
```bash
# Re-run IAM setup
./07_setup_iam_policies.sh

# Check dynamic group matching rules
# Verify policy statements in OCI Console
```

### Debug Commands

```bash
# Test function locally
echo '{"data":{"resourceName":"test-file.csv.gz"}}' | python3 func.py

# Test deployed function
echo '{"data":{"resourceName":"test-file.csv.gz"}}' | fn invoke [app-name] send-usage-report

# Check function logs
oci logging-search search-logs --search-query "search \"[function-ocid]\""

# Validate configuration
./load_config.sh --show
```

## 📚 OCI Documentation Links

### Core Services
- **[OCI Functions](https://docs.oracle.com/en-us/iaas/Content/Functions/Concepts/functionsoverview.htm)** - Serverless compute platform
- **[Object Storage](https://docs.oracle.com/en-us/iaas/Content/Object/Concepts/objectstorageoverview.htm)** - Scalable object storage service
- **[OCI Vault](https://docs.oracle.com/en-us/iaas/Content/KeyManagement/Concepts/keyoverview.htm)** - Key and secret management service
- **[Events Service](https://docs.oracle.com/en-us/iaas/Content/Events/Concepts/eventsoverview.htm)** - Event-driven automation
- **[Email Delivery](https://docs.oracle.com/en-us/iaas/Content/Email/Concepts/overview.htm)** - Transactional email service

### Security and Identity
- **[IAM Policies](https://docs.oracle.com/en-us/iaas/Content/Identity/Concepts/policies.htm)** - Access control and permissions
- **[Dynamic Groups](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/managingdynamicgroups.htm)** - Resource-based group membership
- **[Resource Principal](https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionsaccessingociresources.htm)** - Service-to-service authentication

### Development and Deployment
- **[Fn Project](https://fnproject.io/)** - Open source serverless platform
- **[OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)** - Command line interface
- **[Python SDK](https://docs.oracle.com/en-us/iaas/tools/python/latest/index.html)** - OCI Python SDK documentation

### Learning Resources
- **[Learn OCI](https://learnoci.cloud/)** - Comprehensive OCI learning platform
- **[OCI Architecture Center](https://docs.oracle.com/solutions/)** - Reference architectures and best practices
- **[OCI Free Tier](https://www.oracle.com/cloud/free/)** - Always free cloud services

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: Report bugs and request features via [GitHub Issues](../../issues)
- **Documentation**: Comprehensive docs in [ARCHITECTURE.md](ARCHITECTURE.md) and [CODE_LOGIC.md](CODE_LOGIC.md)
- **OCI Support**: For OCI-specific issues, consult [OCI Documentation](https://docs.oracle.com/en-us/iaas/)

## 🎯 Use Cases

### Automated Cost Reporting
- **Weekly/Monthly Reports**: Automatically email usage reports to stakeholders
- **Cost Monitoring**: Track spending patterns and trends
- **Budget Alerts**: Integrate with cost management workflows

### Compliance and Auditing
- **Automated Documentation**: Maintain audit trails of resource usage
- **Regulatory Reporting**: Generate compliance reports automatically
- **Historical Analysis**: Archive and analyze usage patterns over time

### Multi-Tenancy Management
- **Department Reporting**: Send usage reports to different departments
- **Project Tracking**: Monitor resource usage by project or team
- **Chargeback Automation**: Automate internal billing processes

---

**Built with ❤️ for the OCI community**

For more OCI automation examples and best practices, visit [Learn OCI](https://learnoci.cloud/).
