#!/usr/bin/env bash
# switch_traffic.sh — atomically shifts prod traffic to new color
# Usage: ./scripts/switch_traffic.sh <new_color> <old_color>
# Optional: CANARY=true for staged rollout (10% → 50% → 100%)

set -euo pipefail

NEW_COLOR="${1:?Usage: switch_traffic.sh <new_color> <old_color>}"
OLD_COLOR="${2:?Usage: switch_traffic.sh <new_color> <old_color>}"
CANARY="${CANARY:-false}"

PROD_LISTENER_ARN="${PROD_LISTENER_ARN:?required}"
TEST_LISTENER_ARN="${TEST_LISTENER_ARN:?required}"
TG_BLUE_ARN="${TG_BLUE_ARN:?required}"
TG_GREEN_ARN="${TG_GREEN_ARN:?required}"
ALB_DNS="${ALB_DNS:?required}"

if [[ "$NEW_COLOR" == "blue" ]]; then
  NEW_TG="$TG_BLUE_ARN"
  OLD_TG="$TG_GREEN_ARN"
else
  NEW_TG="$TG_GREEN_ARN"
  OLD_TG="$TG_BLUE_ARN"
fi

switch_weights() {
  local new_weight=$1
  local old_weight=$2
  echo "  → ${NEW_COLOR}=${new_weight}% / ${OLD_COLOR}=${old_weight}%"
  aws elbv2 modify-listener \
    --listener-arn "$PROD_LISTENER_ARN" \
    --default-actions "[{
      \"Type\": \"forward\",
      \"ForwardConfig\": {
        \"TargetGroups\": [
          {\"TargetGroupArn\": \"$NEW_TG\", \"Weight\": $new_weight},
          {\"TargetGroupArn\": \"$OLD_TG\", \"Weight\": $((100 - new_weight))}
        ]
      }
    }]" > /dev/null
}

update_test_listener() {
  local idle_color=$1
  local idle_tg
  [[ "$idle_color" == "blue" ]] && idle_tg="$TG_BLUE_ARN" || idle_tg="$TG_GREEN_ARN"
  aws elbv2 modify-listener \
    --listener-arn "$TEST_LISTENER_ARN" \
    --default-actions "[{\"Type\":\"forward\",\"TargetGroupArn\":\"$idle_tg\"}]" > /dev/null
  echo "  → Test listener now points to $idle_color (new idle)"
}

echo ""
echo "🔀 Switching traffic: $OLD_COLOR → $NEW_COLOR"
echo "   Prod listener: $PROD_LISTENER_ARN"

if [[ "$CANARY" == "true" ]]; then
  echo ""
  echo "📊 Canary mode: staged rollout"
  switch_weights 10 90
  echo "  ⏳ 10% canary — waiting 60s..."
  sleep 60

  # Check for errors at 10%
  ERRORS=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/ApplicationELB \
    --metric-name HTTPCode_Target_5XX_Count \
    --dimensions Name=TargetGroup,Value="$(basename $NEW_TG)" \
    --start-time "$(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 120 --statistics Sum \
    --query 'Datapoints[0].Sum' --output text 2>/dev/null || echo "0")

  if [[ "${ERRORS:-0}" != "None" && "${ERRORS:-0}" -gt 5 ]]; then
    echo "  ❌ Too many errors at 10% canary ($ERRORS 5xx). Aborting."
    switch_weights 0 100
    exit 1
  fi

  switch_weights 50 50
  echo "  ⏳ 50% canary — waiting 60s..."
  sleep 60
fi

# Full switch
switch_weights 100 0
echo "✅ Traffic fully switched to $NEW_COLOR"

# Update test listener to point at now-idle old environment
update_test_listener "$OLD_COLOR"

# Store last-active color in SSM for rollback reference
aws ssm put-parameter \
  --name "/bluegreen/last_active" \
  --value "$OLD_COLOR" \
  --type String \
  --overwrite > /dev/null 2>&1 || true

echo ""
echo "Verifying cutover..."
for i in {1..5}; do
  RESPONSE=$(curl -sf "http://${ALB_DNS}/version" 2>/dev/null || echo '{}')
  COLOR=$(echo "$RESPONSE" | jq -r '.color // "unknown"')
  VERSION=$(echo "$RESPONSE" | jq -r '.version // "unknown"')
  echo "  Request $i: color=$COLOR version=$VERSION"
  sleep 1
done
