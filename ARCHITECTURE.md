# OCI Report Automation - Architecture & Logic Documentation

## System Overview

The OCI Report Automation system is a serverless, event-driven solution that automatically processes and emails OCI usage reports when they are uploaded to Object Storage. The system uses OCI Functions, Resource Principal authentication, and integrates with multiple OCI services.

## Architecture Diagram

```mermaid
graph TB
    subgraph "OCI Tenancy"
        subgraph "Object Storage"
            OSB[Object Storage Bucket<br/>monthly-usage-reports]
            RPT[Usage Report Files<br/>WeeklyCostsScheduledReport_*.csv.gz]
        end
        
        subgraph "Events Service"
            ER[Event Rule<br/>Object Create/Update]
        end
        
        subgraph "Functions Service"
            FA[Function Application<br/>usagereports]
            FN[Function<br/>send-usage-report]
        end
        
        subgraph "Vault Service"
            VLT[OCI Vault]
            SEC1[Secret: SMTP Username]
            SEC2[Secret: SMTP Password]
        end
        
        subgraph "Email Delivery"
            SMTP[SMTP Server<br/>smtp.email.region.oci.oraclecloud.com]
        end
        
        subgraph "IAM & Security"
            DG[Dynamic Group<br/>usagereports-function-dg]
            POL[IAM Policy<br/>usagereports-function-policy]
            RP[Resource Principal]
        end
        
        subgraph "Logging"
            LOG[OCI Logging Service]
        end
    end
    
    subgraph "External"
        EMAIL[Email Recipients<br/>user@example.com]
    end
    
    %% Data Flow
    RPT --> OSB
    OSB --> ER
    ER --> FN
    FN --> OSB
    FN --> VLT
    VLT --> SEC1
    VLT --> SEC2
    FN --> SMTP
    SMTP --> EMAIL
    FN --> LOG
    
    %% Security Flow
    FN --> RP
    RP --> DG
    DG --> POL
    POL --> OSB
    POL --> VLT
    
    %% Styling
    classDef storage fill:#e1f5fe
    classDef compute fill:#f3e5f5
    classDef security fill:#fff3e0
    classDef external fill:#e8f5e8
    
    class OSB,RPT storage
    class FA,FN,ER compute
    class DG,POL,RP,VLT,SEC1,SEC2 security
    class EMAIL,SMTP external
```

## Component Architecture

### 1. Trigger Layer
- **Object Storage Bucket**: Stores usage report files
- **Event Rule**: Monitors bucket for new/updated files
- **Event Payload**: Contains file metadata and triggers function

### 2. Compute Layer
- **OCI Function**: Serverless compute that processes events
- **Function Application**: Container for the function
- **Runtime Environment**: Python 3.11 with required dependencies

### 3. Security Layer
- **Resource Principal**: Enables function to authenticate without credentials
- **Dynamic Group**: Groups function resources for policy application
- **IAM Policies**: Grant specific permissions to function resources
- **OCI Vault**: Securely stores SMTP credentials

### 4. Integration Layer
- **Object Storage Client**: Downloads report files
- **Secrets Client**: Retrieves SMTP credentials
- **SMTP Client**: Sends emails with attachments
- **Logging Service**: Captures function execution logs

## Detailed Logic Flow

### Phase 1: Event Trigger
```mermaid
sequenceDiagram
    participant User as User/System
    participant OSB as Object Storage
    participant ER as Event Rule
    participant FN as Function
    
    User->>OSB: Upload usage report file
    OSB->>ER: Object created/updated event
    ER->>FN: Trigger function with event payload
    Note over FN: Event contains:<br/>- resourceName<br/>- bucketName<br/>- namespace
```

### Phase 2: Function Initialization
```mermaid
sequenceDiagram
    participant FN as Function Handler
    participant RP as Resource Principal
    participant LOG as Logging
    
    FN->>LOG: Log function start
    FN->>FN: Parse event payload
    FN->>FN: Extract object name
    FN->>RP: Initialize authentication
    FN->>FN: Validate environment variables
    FN->>LOG: Log initialization complete
```

### Phase 3: File Processing
```mermaid
sequenceDiagram
    participant FN as Function
    participant OSC as Object Storage Client
    participant OSB as Object Storage Bucket
    
    FN->>OSC: Initialize client with Resource Principal
    FN->>OSC: Get object request
    OSC->>OSB: Download file
    OSB->>OSC: Return file data
    OSC->>FN: File content (bytes)
    FN->>FN: Validate file size and format
```

### Phase 4: Credential Retrieval
```mermaid
sequenceDiagram
    participant FN as Function
    participant SC as Secrets Client
    participant VLT as Vault
    
    FN->>SC: Initialize client with Resource Principal
    FN->>SC: Get secret bundle (username)
    SC->>VLT: Retrieve secret
    VLT->>SC: Return encrypted secret
    SC->>FN: Decoded username
    FN->>SC: Get secret bundle (password)
    SC->>VLT: Retrieve secret
    VLT->>SC: Return encrypted secret
    SC->>FN: Decoded password
```

### Phase 5: Email Composition
```mermaid
sequenceDiagram
    participant FN as Function
    participant EMAIL as Email Builder
    
    FN->>EMAIL: Create MIME multipart message
    FN->>EMAIL: Set headers (From, To, Subject)
    FN->>EMAIL: Add text body
    FN->>EMAIL: Attach file with base64 encoding
    EMAIL->>FN: Complete email message
```

### Phase 6: Email Delivery
```mermaid
sequenceDiagram
    participant FN as Function
    participant SMTP as SMTP Server
    participant RECIP as Recipient
    
    FN->>SMTP: Connect to server
    FN->>SMTP: Start TLS encryption
    FN->>SMTP: Authenticate with credentials
    FN->>SMTP: Send email message
    SMTP->>RECIP: Deliver email
    SMTP->>FN: Delivery confirmation
    FN->>FN: Log success and return response
```

## Security Architecture

### Resource Principal Authentication Flow
```mermaid
graph LR
    subgraph "Function Execution"
        FN[Function Instance]
    end
    
    subgraph "IAM Service"
        RP[Resource Principal]
        DG[Dynamic Group]
        POL[IAM Policy]
    end
    
    subgraph "Target Resources"
        OSB[Object Storage]
        VLT[Vault Secrets]
    end
    
    FN --> RP
    RP --> DG
    DG --> POL
    POL --> OSB
    POL --> VLT
    
    classDef function fill:#f9f,stroke:#333,stroke-width:2px
    classDef security fill:#bbf,stroke:#333,stroke-width:2px
    classDef resource fill:#bfb,stroke:#333,stroke-width:2px
    
    class FN function
    class RP,DG,POL security
    class OSB,VLT resource
```

### Permission Matrix
| Resource | Permission | Scope | Purpose |
|----------|------------|-------|---------|
| Object Storage | `read objects` | Specific bucket | Download usage reports |
| Vault Secrets | `read secret-bundles` | Specific vault | Retrieve SMTP credentials |
| Functions | `use fn-invocation` | Compartment | Function execution |
| Object Storage | `read objectstorage-namespaces` | Tenancy | Namespace operations |
| Compartments | `inspect compartments` | Tenancy | Compartment validation |

## Data Flow Architecture

### Input Data Structure
```json
{
  "eventType": "com.oraclecloud.objectstorage.createobject",
  "source": "ObjectStorage",
  "eventTypeVersion": "2.0",
  "eventTime": "2025-06-24T09:00:00Z",
  "data": {
    "compartmentId": "ocid1.compartment.oc1..aaaa...",
    "compartmentName": "root",
    "resourceName": "WeeklyCostsScheduledReport_20250620_0.csv.gz",
    "resourceId": "ocid1.object.oc1..aaaa...",
    "bucketName": "monthly-usage-reports",
    "bucketId": "ocid1.bucket.oc1..aaaa...",
    "namespace": "your-namespace"
  }
}
```

### Function Configuration
```yaml
config:
  BUCKET_NAME: monthly-usage-reports
  EMAIL_FROM: sender@example.com
  EMAIL_TO: recipient@example.com
  NAMESPACE: your-namespace
  REGION: your-region
  SMTP_PASSWORD_SECRET_OCID: ocid1.vaultsecret.oc1..aaaa...
  SMTP_PORT: "587"
  SMTP_SERVER: smtp.email.your-region.oci.oraclecloud.com
  SMTP_USERNAME_SECRET_OCID: ocid1.vaultsecret.oc1..aaaa...
```

### Output Response Structure
```json
{
  "status": "success",
  "message": "Email sent successfully for WeeklyCostsScheduledReport_20250620_0.csv.gz",
  "object_name": "WeeklyCostsScheduledReport_20250620_0.csv.gz",
  "recipient": "recipient@example.com",
  "timestamp": "2025-06-24T09:15:00Z"
}
```

## Error Handling Architecture

### Error Categories and Responses
```mermaid
graph TD
    START[Function Start] --> PARSE[Parse Event]
    PARSE --> |Success| AUTH[Authenticate]
    PARSE --> |Failure| ERR1[Parse Error]
    
    AUTH --> |Success| VALIDATE[Validate Environment]
    AUTH --> |Failure| ERR2[Auth Error]
    
    VALIDATE --> |Success| DOWNLOAD[Download File]
    VALIDATE --> |Failure| ERR3[Config Error]
    
    DOWNLOAD --> |Success| SECRETS[Get Secrets]
    DOWNLOAD --> |Failure| ERR4[Storage Error]
    
    SECRETS --> |Success| EMAIL[Send Email]
    SECRETS --> |Failure| ERR5[Vault Error]
    
    EMAIL --> |Success| SUCCESS[Success Response]
    EMAIL --> |Failure| ERR6[SMTP Error]
    
    ERR1 --> LOG[Log Error]
    ERR2 --> LOG
    ERR3 --> LOG
    ERR4 --> LOG
    ERR5 --> LOG
    ERR6 --> LOG
    
    LOG --> RESPONSE[Error Response]
    
    classDef success fill:#d4edda
    classDef error fill:#f8d7da
    classDef process fill:#d1ecf1
    
    class SUCCESS success
    class ERR1,ERR2,ERR3,ERR4,ERR5,ERR6,RESPONSE error
    class START,PARSE,AUTH,VALIDATE,DOWNLOAD,SECRETS,EMAIL,LOG process
```

## Deployment Architecture

### Infrastructure Components
```mermaid
graph TB
    subgraph "Development Environment"
        DEV[Local Development]
        CLI[OCI CLI]
        FN_CLI[Fn CLI]
        DOCKER[Docker]
    end
    
    subgraph "CI/CD Pipeline"
        BUILD[Build Function]
        TEST[Test Function]
        DEPLOY[Deploy Function]
    end
    
    subgraph "OCI Infrastructure"
        REGISTRY[Container Registry]
        FUNCTIONS[Functions Service]
        COMPUTE[Compute Infrastructure]
    end
    
    DEV --> BUILD
    CLI --> BUILD
    FN_CLI --> BUILD
    DOCKER --> BUILD
    
    BUILD --> TEST
    TEST --> DEPLOY
    DEPLOY --> REGISTRY
    REGISTRY --> FUNCTIONS
    FUNCTIONS --> COMPUTE
    
    classDef dev fill:#e3f2fd
    classDef cicd fill:#f3e5f5
    classDef infra fill:#e8f5e8
    
    class DEV,CLI,FN_CLI,DOCKER dev
    class BUILD,TEST,DEPLOY cicd
    class REGISTRY,FUNCTIONS,COMPUTE infra
```

### Deployment Scripts Flow
```mermaid
graph LR
    MAIN[main_setup.sh] --> PREREQ[01_prerequisites_check.sh]
    PREREQ --> BUCKET[02_bucket_setup.sh]
    BUCKET --> VAULT[03_vault_secrets_setup.sh]
    VAULT --> EMAIL[04_email_delivery_setup.sh]
    EMAIL --> FUNCTION[05_function_deploy.sh]
    FUNCTION --> IAM[07_setup_iam_policies.sh]
    IAM --> EVENT[08_create_event_rule.sh]
    EVENT --> TEST[06_test_send.sh]
    
    classDef script fill:#fff3e0,stroke:#ff9800,stroke-width:2px
    class MAIN,PREREQ,BUCKET,VAULT,EMAIL,FUNCTION,IAM,EVENT,TEST script
```

## Monitoring and Observability

### Logging Architecture
```mermaid
graph TB
    subgraph "Function Execution"
        FN[Function Instance]
        LOGS[Function Logs]
    end
    
    subgraph "OCI Logging"
        SYSLOG[Syslog Endpoint]
        LOG_SERVICE[Logging Service]
        LOG_GROUPS[Log Groups]
    end
    
    subgraph "Monitoring"
        METRICS[Function Metrics]
        ALARMS[CloudWatch Alarms]
        DASHBOARD[Monitoring Dashboard]
    end
    
    FN --> LOGS
    LOGS --> SYSLOG
    SYSLOG --> LOG_SERVICE
    LOG_SERVICE --> LOG_GROUPS
    
    FN --> METRICS
    METRICS --> ALARMS
    METRICS --> DASHBOARD
    
    classDef function fill:#e1f5fe
    classDef logging fill:#f3e5f5
    classDef monitoring fill:#e8f5e8
    
    class FN,LOGS function
    class SYSLOG,LOG_SERVICE,LOG_GROUPS logging
    class METRICS,ALARMS,DASHBOARD monitoring
```

### Key Metrics Tracked
- Function invocation count
- Function execution duration
- Function error rate
- Memory utilization
- Email delivery success rate
- File processing time

## Scalability and Performance

### Auto-scaling Characteristics
- **Concurrent Executions**: Up to 1000 concurrent function instances
- **Memory Allocation**: 512MB per instance (configurable)
- **Timeout**: 120 seconds per execution
- **Cold Start**: ~2-3 seconds for Python runtime
- **Warm Execution**: ~100-500ms

### Performance Optimization
- Resource Principal authentication (no credential lookup)
- Efficient file streaming from Object Storage
- Minimal memory footprint for email composition
- Optimized Docker image with required dependencies only

## Disaster Recovery and High Availability

### Fault Tolerance
- **Multi-AZ Deployment**: Functions automatically distributed across availability domains
- **Automatic Retry**: Event service retries failed function invocations
- **Dead Letter Queue**: Failed events can be routed to DLQ for analysis
- **Circuit Breaker**: Function service handles overload scenarios

### Backup and Recovery
- **Configuration Backup**: All configuration stored in version-controlled scripts
- **Secret Rotation**: Vault secrets can be rotated without function redeployment
- **Infrastructure as Code**: Complete infrastructure reproducible via scripts

This architecture provides a robust, scalable, and secure solution for automated OCI usage report processing and delivery.
