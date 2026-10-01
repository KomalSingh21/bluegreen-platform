#!/usr/bin/env bash
# smoke_test.sh — runs against the IDLE environment via the test listener (:8443)
# Usage: ./scripts/smoke_test.sh <expected_version>
# Exits 0 on pass, 1 on failure. Safe: prod traffic is never touched.

set -euo pipefail

EXPECTED_VERSION="${1:?Usage: smoke_test.sh <expected_version>}"
ALB_DNS="${ALB_DNS:?ALB_DNS env var required}"
TEST_PORT="${TEST_PORT:-8443}"
BASE_URL="http://${ALB_DNS}:${TEST_PORT}"

PASS=0
FAIL=0

check() {
  local name="$1"
  local cmd="$2"
  local expect="$3"

  echo -n "  [$name] "
  result=$(eval "$cmd" 2>&1) || true

  if echo "$result" | grep -q "$expect"; then
    echo "✅ PASS"
    ((PASS++)) || true
  else
    echo "❌ FAIL — expected '$expect', got: $result"
    ((FAIL++)) || true
  fi
}

echo "🔍 Smoke testing idle environment via test listener ($BASE_URL)"
echo "   Expected version: $EXPECTED_VERSION"
echo ""

# 1. Health check returns 200
check "health-status" \
  "curl -sf ${BASE_URL}/health | jq -r .status" \
  "healthy"

# 2. Version matches the image we deployed
check "version-match" \
  "curl -sf ${BASE_URL}/version | jq -r .version" \
  "$EXPECTED_VERSION"

# 3. Main API endpoint works
check "api-hello" \
  "curl -sf ${BASE_URL}/api/hello | jq -r .message" \
  "Hello"

# 4. No 5xx on repeated calls
echo -n "  [5xx-stress] "
ERRORS=0
for i in {1..20}; do
  STATUS=$(curl -so /dev/null -w "%{http_code}" "${BASE_URL}/api/hello") || true
  [[ "$STATUS" == "200" ]] || ((ERRORS++)) || true
done
if [[ $ERRORS -eq 0 ]]; then
  echo "✅ PASS (0 errors in 20 requests)"
  ((PASS++)) || true
else
  echo "❌ FAIL ($ERRORS errors in 20 requests)"
  ((FAIL++)) || true
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  echo "❌ Smoke tests FAILED — NOT switching traffic"
  exit 1
fi

echo "✅ All smoke tests passed — safe to switch traffic"
exit 0
