#!/usr/bin/env bash
# get_active.sh — prints "blue" or "green" (the currently active color)
# Usage: ./scripts/get_active.sh
# Outputs: active color to stdout, idle color to stderr (for pipeline use)

set -euo pipefail

PROD_LISTENER_ARN="${PROD_LISTENER_ARN:?PROD_LISTENER_ARN env var required}"
TG_BLUE_ARN="${TG_BLUE_ARN:?TG_BLUE_ARN env var required}"
TG_GREEN_ARN="${TG_GREEN_ARN:?TG_GREEN_ARN env var required}"

# Get the target group currently receiving 100% of prod traffic
ACTIVE_TG=$(aws elbv2 describe-listeners \
  --listener-arns "$PROD_LISTENER_ARN" \
  --query 'Listeners[0].DefaultActions[0].ForwardConfig.TargetGroups[?Weight==`100`].TargetGroupArn' \
  --output text 2>/dev/null)

# Fallback: if weighted config not found, check simple forward action
if [[ -z "$ACTIVE_TG" ]]; then
  ACTIVE_TG=$(aws elbv2 describe-listeners \
    --listener-arns "$PROD_LISTENER_ARN" \
    --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
    --output text)
fi

if [[ "$ACTIVE_TG" == "$TG_BLUE_ARN" ]]; then
  ACTIVE="blue"
  IDLE="green"
elif [[ "$ACTIVE_TG" == "$TG_GREEN_ARN" ]]; then
  ACTIVE="green"
  IDLE="blue"
else
  echo "ERROR: Could not determine active color. TG: $ACTIVE_TG" >&2
  exit 1
fi

echo "$ACTIVE"
echo "$IDLE" >&2
