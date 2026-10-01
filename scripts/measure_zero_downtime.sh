#!/usr/bin/env bash
# measure_zero_downtime.sh
# Continuously checks application health during a deployment.
# Writes results to docs/zero-downtime-results.md

set -euo pipefail

ALB_DNS="${ALB_DNS:?required}"
DURATION="${1:-180}"
INTERVAL="${2:-0.2}"

URL="http://${ALB_DNS}/health"

TOTAL=0
SUCCESS=0
FAILED=0

START_TIME=$(date +%s)

echo "📊 Zero-Downtime Measurement"
echo "   Target: $URL"
echo "   Duration: ${DURATION}s"
echo "   Interval: ${INTERVAL}s"
echo ""
echo "🚀 Start your deployment now."
echo ""

while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))

    if (( ELAPSED >= DURATION )); then
        break
    fi

    TOTAL=$((TOTAL + 1))

    if curl -sf --max-time 3 "$URL" > /dev/null 2>&1; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILED=$((FAILED + 1))
    fi

    sleep "$INTERVAL"
done

END_TIME=$(date +%s)
ACTUAL_DURATION=$((END_TIME - START_TIME))

if (( TOTAL > 0 )); then
    AVAILABILITY=$(awk "BEGIN { printf \"%.2f\", ($SUCCESS / $TOTAL) * 100 }")
    FAILURE_RATE=$(awk "BEGIN { printf \"%.2f\", ($FAILED / $TOTAL) * 100 }")
else
    AVAILABILITY="0.00"
    FAILURE_RATE="0.00"
fi

echo ""
echo "══════════════════════════════════════"
echo " Zero-Downtime Results"
echo "══════════════════════════════════════"
echo "  Duration:       ${ACTUAL_DURATION}s"
echo "  Total requests: $TOTAL"
echo "  Successful:     $SUCCESS"
echo "  Failed:         $FAILED"
echo "  Availability:   ${AVAILABILITY}%"
echo "  Failure rate:   ${FAILURE_RATE}%"

if (( FAILED == 0 )); then
    echo "  ✅ No failed health checks"
else
    echo "  ⚠️ Failed health checks detected"
fi

cat > docs/zero-downtime-results.md << EOF
# Zero-Downtime Deployment Results

**Date:** $(date -u)
**Target:** \`$URL\`
**Duration:** ${ACTUAL_DURATION}s

| Metric | Result |
|---|---:|
| Total requests | $TOTAL |
| Successful requests | $SUCCESS |
| Failed requests | $FAILED |
| Availability | ${AVAILABILITY}% |
| Failure rate | ${FAILURE_RATE}% |

## Result

$([ "$FAILED" -eq 0 ] \
  && echo "✅ No failed health checks were observed during the measurement window." \
  || echo "⚠️ Failed health checks were observed during the measurement window.")
EOF

echo ""
echo "Results saved to docs/zero-downtime-results.md"
