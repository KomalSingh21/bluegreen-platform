#!/usr/bin/env bash
# measure_rollback_sla.sh — measures rollback time end-to-end, 5 runs
# Writes results to docs/sla-results.md for the interview portfolio

set -euo pipefail

RUNS="${1:-5}"
RESULTS=()
ALB_DNS="${ALB_DNS:?required}"

echo "📏 Rollback SLA Measurement"
echo "   Runs: $RUNS"
echo "   Target SLA: <60s"
echo ""

for i in $(seq 1 $RUNS); do
  echo "─── Run $i/$RUNS ────────────────────────────"

  # Get baseline color
  CURRENT=$(./scripts/get_active.sh)
  [[ "$CURRENT" == "blue" ]] && TARGET="green" || TARGET="blue"
  echo "  Current: $CURRENT → Rolling back to: $TARGET"

  # Switch to opposite to set up the rollback scenario
  CANARY=false ./scripts/switch_traffic.sh "$TARGET" "$CURRENT" > /dev/null

  sleep 5   # let traffic settle

  # Now run rollback back to original
  START=$(date +%s%3N)   # milliseconds
  ROLLBACK_REASON="sla-test-run-$i" ./scripts/rollback.sh > /dev/null
  
  # Confirm via polling
  CONFIRMED=false
  while true; do
    COLOR=$(curl -sf "http://${ALB_DNS}/version" | jq -r .color 2>/dev/null || echo "")
    if [[ "$COLOR" == "$CURRENT" ]]; then
      CONFIRMED=true
      break
    fi
    sleep 0.2
  done

  END=$(date +%s%3N)
  DURATION_MS=$(( END - START ))
  DURATION_S=$(echo "scale=1; $DURATION_MS / 1000" | bc)

  echo "  ✅ Confirmed in ${DURATION_S}s"
  RESULTS+=("$DURATION_S")
  sleep 10
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════"
echo " SLA Results ($RUNS runs)"
echo "══════════════════════════════════════"

TOTAL=0
MAX=0
MIN=9999
for r in "${RESULTS[@]}"; do
  echo "  Run: ${r}s"
  TOTAL=$(echo "$TOTAL + $r" | bc)
  if (( $(echo "$r > $MAX" | bc -l) )); then MAX=$r; fi
  if (( $(echo "$r < $MIN" | bc -l) )); then MIN=$r; fi
done

MEAN=$(echo "scale=1; $TOTAL / $RUNS" | bc)

echo ""
echo "  Mean:  ${MEAN}s"
echo "  Min:   ${MIN}s"
echo "  Max:   ${MAX}s"
echo "  SLA:   <60s"
[[ $(echo "$MAX < 60" | bc -l) -eq 1 ]] \
  && echo "  ✅ ALL RUNS WITHIN SLA" \
  || echo "  ❌ SOME RUNS EXCEEDED SLA"

# Write to docs
cat > docs/sla-results.md << EOF
# Rollback SLA Results

**Date:** $(date -u)
**Runs:** $RUNS
**SLA Target:** <60 seconds

| Run | Duration |
|-----|----------|
$(for i in "${!RESULTS[@]}"; do echo "| $((i+1)) | ${RESULTS[$i]}s |"; done)

**Mean:** ${MEAN}s
**Min:** ${MIN}s
**Max:** ${MAX}s
**SLA Met:** $([ $(echo "$MAX < 60" | bc -l) -eq 1 ] && echo "✅ Yes" || echo "❌ No")
EOF

echo ""
echo "Results saved to docs/sla-results.md"
