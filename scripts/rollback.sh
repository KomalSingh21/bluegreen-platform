#!/usr/bin/env bash
# rollback.sh — reverts prod traffic to the previous (idle) environment instantly.
# Usage: ./scripts/rollback.sh [--reason "description"]
# Target: under 60 seconds from call to traffic restored.

set -euo pipefail

REASON="${2:-manual}"
PROD_LISTENER_ARN="${PROD_LISTENER_ARN:?required}"
TEST_LISTENER_ARN="${TEST_LISTENER_ARN:?required}"
TG_BLUE_ARN="${TG_BLUE_ARN:?required}"
TG_GREEN_ARN="${TG_GREEN_ARN:?required}"
ALB_DNS="${ALB_DNS:?required}"

START_TIME=$(date +%s)
echo ""
echo "🚨 ROLLBACK INITIATED"
echo "   Reason: $REASON"
echo "   Time:   $(date -u)"

# ── Determine current active and rollback target ───────────────────────────────
ACTIVE=$(./scripts/get_active.sh 2>/dev/null || echo "unknown")

if [[ "$ACTIVE" == "blue" ]]; then
  ROLLBACK_TO="green"
  ROLLBACK_TG="$TG_GREEN_ARN"
  CURRENT_TG="$TG_BLUE_ARN"
elif [[ "$ACTIVE" == "green" ]]; then
  ROLLBACK_TO="blue"
  ROLLBACK_TG="$TG_BLUE_ARN"
  CURRENT_TG="$TG_GREEN_ARN"
else
  # Fallback: read from SSM
  ROLLBACK_TO=$(aws ssm get-parameter \
    --name "/bluegreen/last_active" \
    --query Parameter.Value --output text 2>/dev/null || echo "blue")
  echo "  ℹ️  Could not detect active color; using SSM fallback: $ROLLBACK_TO"
  [[ "$ROLLBACK_TO" == "blue" ]] && ROLLBACK_TG="$TG_BLUE_ARN" || ROLLBACK_TG="$TG_GREEN_ARN"
fi

echo "   Rolling back to: $ROLLBACK_TO"

# ── Switch ALB listener (the one API call that matters) ────────────────────────
aws elbv2 modify-listener \
  --listener-arn "$PROD_LISTENER_ARN" \
  --default-actions "[{
    \"Type\": \"forward\",
    \"ForwardConfig\": {
      \"TargetGroups\": [
        {\"TargetGroupArn\": \"$ROLLBACK_TG\", \"Weight\": 100},
        {\"TargetGroupArn\": \"$CURRENT_TG\",  \"Weight\": 0}
      ]
    }
  }]" > /dev/null

SWITCH_TIME=$(( $(date +%s) - START_TIME ))
echo "✅ Listener updated in ${SWITCH_TIME}s"

# ── Update test listener ───────────────────────────────────────────────────────
ACTIVE_AFTER_ROLLBACK="$ACTIVE"   # the broken color; now idle
[[ "$ACTIVE" == "blue" ]] && IDLE_TG="$TG_BLUE_ARN" || IDLE_TG="$TG_GREEN_ARN"
aws elbv2 modify-listener \
  --listener-arn "$TEST_LISTENER_ARN" \
  --default-actions "[{\"Type\":\"forward\",\"TargetGroupArn\":\"$IDLE_TG\"}]" > /dev/null

# ── Wait for traffic to confirm rollback ──────────────────────────────────────
echo ""
echo "Waiting for traffic to confirm rollback..."
MAX_WAIT=30
CONFIRMED=false
for i in $(seq 1 $MAX_WAIT); do
  RESPONSE=$(curl -sf "http://${ALB_DNS}/version" 2>/dev/null || echo '{}')
  COLOR=$(echo "$RESPONSE" | jq -r '.color // "unknown"')
  if [[ "$COLOR" == "$ROLLBACK_TO" ]]; then
    CONFIRMED=true
    break
  fi
  sleep 1
done

END_TIME=$(date +%s)
TOTAL_TIME=$(( END_TIME - START_TIME ))

if $CONFIRMED; then
  echo "✅ ROLLBACK COMPLETE in ${TOTAL_TIME}s (target: <60s)"
  echo "   Traffic confirmed on: $ROLLBACK_TO"
else
  echo "⚠️  Traffic switch sent but not yet confirmed after ${MAX_WAIT}s"
  echo "   Total elapsed: ${TOTAL_TIME}s"
  echo "   Check ALB target group health in AWS Console"
fi

# Log rollback event
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"from\":\"$ACTIVE\",\"to\":\"$ROLLBACK_TO\",\"reason\":\"$REASON\",\"duration_s\":$TOTAL_TIME}" \
  >> docs/rollback-history.jsonl 2>/dev/null || true
