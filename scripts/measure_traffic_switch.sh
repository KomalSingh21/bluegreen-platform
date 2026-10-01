#!/usr/bin/env bash
# measure_traffic_switch.sh
# Measures ALB blue/green traffic switch time.

set -euo pipefail

ALB_DNS="${ALB_DNS:?required}"
TARGET="${1:?usage: ./scripts/measure_traffic_switch.sh blue|green}"

if [[ "$TARGET" != "blue" && "$TARGET" != "green" ]]; then
    echo "ERROR: target must be blue or green"
    exit 1
fi

CURRENT=$(./scripts/get_active.sh)

if [[ "$CURRENT" == "$TARGET" ]]; then
    echo "Traffic is already on $TARGET."
    exit 0
fi

echo "📡 Traffic Switch Measurement"
echo "   Current: $CURRENT"
echo "   Target:  $TARGET"
echo ""

START=$(date +%s%3N)

./scripts/switch_traffic.sh "$TARGET" "$CURRENT" > /dev/null

echo "Traffic switch initiated..."

TIMEOUT=60

while true; do

    COLOR=$(curl -sf \
        --max-time 3 \
        "http://${ALB_DNS}/version" 2>/dev/null \
        | jq -r '.color' 2>/dev/null || echo "")

    if [[ "$COLOR" == "$TARGET" ]]; then
        END=$(date +%s%3N)
        break
    fi

    NOW=$(date +%s)
    START_SEC=$((START / 1000))

    if (( NOW - START_SEC >= TIMEOUT )); then
        echo "❌ Traffic switch did not complete within ${TIMEOUT}s"
        exit 1
    fi

    sleep 0.2
done

DURATION_MS=$((END - START))
DURATION_S=$(awk "BEGIN { printf \"%.2f\", $DURATION_MS / 1000 }")

echo ""
echo "══════════════════════════════════════"
echo " Traffic Switch Results"
echo "══════════════════════════════════════"
echo "  From:       $CURRENT"
echo "  To:         $TARGET"
echo "  Switch time: ${DURATION_S}s"
echo "  Status:     ✅ Successful"

cat > docs/traffic-switch-results.md << EOF
# Traffic Switch Results

**Date:** $(date -u)

| Metric | Result |
|---|---:|
| Previous traffic | $CURRENT |
| New traffic | $TARGET |
| Switch time | ${DURATION_S}s |
| Status | ✅ Successful |
EOF

echo ""
echo "Results saved to docs/traffic-switch-results.md"
