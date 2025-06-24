#!/bin/bash

# 08_create_event_rule.sh
# Creates an OCI Event Rule to trigger the function when new objects are uploaded to the bucket

set -euo pipefail

echo "--- [ Step 8: OCI Event Rule Setup ] ---"

# Load configuration
source ./load_config.sh
load_config
validate_config

# Update config.env helper
update_config_value() {
    local key="$1"
    local value="$2"
    local config_file="${3:-config.env}"

    if [[ -f "$config_file" ]]; then
        if grep -q "^${key}=" "$config_file"; then
            sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$config_file"
        else
            echo "${key}=\"${value}\"" >> "$config_file"
        fi
    else
        echo "${key}=\"${value}\"" > "$config_file"
    fi
}

# Validate required variables from config.env
REQUIRED_VARS=("REPORT_BUCKET_NAME" "FUNCTION_APP_NAME" "COMPARTMENT_OCID" "NAMESPACE")
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required variable: $var"
    exit 1
  fi
done

BUCKET_NAME="$REPORT_BUCKET_NAME"
APP_NAME="$FUNCTION_APP_NAME"
COMP_ID="$COMPARTMENT_OCID"
REGION="${REGION:-eu-frankfurt-1}"

# Get application OCID
APP_OCID=$(oci fn application list \
  --compartment-id "$COMP_ID" \
  --query "data[?\"display-name\"=='$APP_NAME'].id | [0]" \
  --raw-output)

if [[ -z "$APP_OCID" ]]; then
  echo "Function application '$APP_NAME' not found in compartment."
  exit 1
fi

# Get function OCID
FN_OCID=$(oci fn function list \
  --application-id "$APP_OCID" \
  --query "data[?\"display-name\"=='send-usage-report'].id | [0]" \
  --raw-output)

if [[ -z "$FN_OCID" ]]; then
  echo "Function 'send-usage-report' not found in application '$APP_NAME'."
  exit 1
fi

# --- Precise matching: displayName + condition + functionId ---
CONDITION_JSON="{\"eventType\":\"com.oraclecloud.objectstorage.createobject\",\"data\":{\"additionalDetails\":{\"bucketName\":\"$BUCKET_NAME\"}}}"
RULE_NAME="send-usage-report-rule"
DISPLAY_NAME="Send Usage Report Rule"

echo "Checking for existing rule with same name, condition and function..."

existing_rule_ocid=$(oci events rule list \
  --compartment-id "$COMP_ID" \
  --all \
  --output json | jq -r --arg cond "$CONDITION_JSON" --arg fn "$FN_OCID" --arg name "$DISPLAY_NAME" '
    .data[] 
    | select(
        .displayName == $name 
        and .condition == $cond 
        and (.actions.actions | type == "array") 
        and (.actions.actions[0].functionId // empty) == $fn
    ) 
    | .id
  ' | head -n 1)

if [[ -n "$existing_rule_ocid" ]]; then
  echo "Matching rule already exists: $existing_rule_ocid"
  update_config_value "EVENT_RULE_OCID" "$existing_rule_ocid"
  update_config_value "EVENT_RULE_NAME" "$RULE_NAME"
  echo "Skipping rule creation."
  exit 0
fi

# Define actions JSON
ACTIONS_JSON=$(cat <<EOF
{
  "actions": [
    {
      "actionType": "FAAS",
      "functionId": "$FN_OCID",
      "isEnabled": true
    }
  ]
}
EOF
)

# Create event rule
echo "Creating rule '$RULE_NAME'..."
RULE_OCID=$(oci events rule create \
  --compartment-id "$COMP_ID" \
  --display-name "$DISPLAY_NAME" \
  --is-enabled true \
  --condition "$CONDITION_JSON" \
  --actions "$ACTIONS_JSON" \
  --freeform-tags '{"CreatedBy":"oci-report-automation"}' \
  --query "data.id" \
  --raw-output)

if [[ -z "$RULE_OCID" ]]; then
  echo "Failed to create rule."
  exit 1
fi

echo "Rule created: $RULE_OCID"

# Wait for rule to become ACTIVE
echo -n "Waiting for rule to become ACTIVE"
for i in {1..15}; do
  STATUS=$(oci events rule get --rule-id "$RULE_OCID" --query "data.\"lifecycle-state\"" --raw-output)
  if [[ "$STATUS" == "ACTIVE" ]]; then
    echo ""
    echo "Rule is ACTIVE."
    break
  fi
  sleep 5
  echo -n "."
  if [[ $i -eq 15 ]]; then
    echo ""
    echo "Timeout waiting for rule to become ACTIVE. Current state: $STATUS"
    exit 1
  fi
done

# Save rule metadata
update_config_value "EVENT_RULE_OCID" "$RULE_OCID"
update_config_value "EVENT_RULE_NAME" "$RULE_NAME"