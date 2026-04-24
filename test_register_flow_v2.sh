#!/bin/bash

# Test Register Flow (Enhanced)
# Tests the complete flow: UserRegistry registration → OpenResponses registration
# Created: 2026-04-24

# Configuration
USER_REGISTRY_HOST="http://192.168.1.173"
USER_REGISTRY_PORT="3100"
OPENRESPONSES_HOST="http://192.168.1.173"
OPENRESPONSES_PORT="18789"
BEARER_TOKEN="21c9e6fa03ca7784e68a2e096253c7490dd192467fbce904"

echo "=== Testing Register Flow ==="
echo ""

# Pre-flight checks
echo "Pre-flight Checks:"
echo "-----------------"

# Check UserRegistry
echo -n "1. UserRegistry (${USER_REGISTRY_HOST}:${USER_REGISTRY_PORT}): "
if curl -s --max-time 5 "${USER_REGISTRY_HOST}:${USER_REGISTRY_PORT}/health" > /dev/null 2>&1; then
    echo "✅ Reachable"
    USER_REGISTRY_OK=true
else
    echo "❌ NOT REACHABLE"
    USER_REGISTRY_OK=false
fi

# Check OpenClaw Gateway
echo -n "2. OpenClaw Gateway (${OPENRESPONSES_HOST}:${OPENRESPONSES_PORT}): "
GATEWAY_HEALTH=$(curl -s --max-time 5 "${OPENRESPONSES_HOST}:${OPENRESPONSES_PORT}/health" 2>&1)
if echo "$GATEWAY_HEALTH" | grep -q "ok"; then
    echo "✅ Reachable"
    OPENCLAW_OK=true
else
    echo "❌ NOT REACHABLE"
    OPENCLAW_OK=false
fi

echo ""

# Decision point
if [ "$USER_REGISTRY_OK" = false ] && [ "$OPENCLAW_OK" = false ]; then
    echo "❌ CANNOT PROCEED: Both services are unreachable"
    echo ""
    echo "Required services:"
    echo "  1. UserRegistry: ${USER_REGISTRY_HOST}:${USER_REGISTRY_PORT}"
    echo "  2. OpenClaw Gateway: ${OPENRESPONSES_HOST}:${OPENRESPONSES_PORT}"
    echo ""
    echo "Please start these services before running the test."
    exit 1
fi

if [ "$USER_REGISTRY_OK" = false ]; then
    echo "⚠️  WARNING: UserRegistry is not reachable"
    echo "   Cannot test face registration (Step 2)"
    echo ""
    echo "To deploy UserRegistry:"
    echo "  cd user-registry"
    echo "  docker-compose up -d"
    echo ""
    echo "Skipping to OpenResponses test with mock user_id..."
    echo ""

    # Use a mock user ID
    USER_ID="00000000-0000-0000-0000-000000000000"
    SKIP_USER_REGISTRY=true
else
    SKIP_USER_REGISTRY=false
fi

if [ "$OPENCLAW_OK" = false ]; then
    echo "⚠️  WARNING: OpenClaw Gateway is not reachable"
    echo "   Cannot test OpenResponses API (Steps 3-4)"
    echo ""
    echo "To start OpenClaw Gateway:"
    echo "  openclaw gateway start"
    echo ""
    exit 1
fi

# Step 1: Create mock embedding
echo "Step 1: Creating mock face embedding..."
MOCK_EMBEDDING="["
for i in $(seq 1 128); do
    RANDOM_FLOAT=$(awk -v min=-1 -v max=1 'BEGIN{srand(); print min+rand()*(max-min)}')
    MOCK_EMBEDDING="${MOCK_EMBEDDING}${RANDOM_FLOAT}"
    if [ $i -lt 128 ]; then
        MOCK_EMBEDDING="${MOCK_EMBEDDING},"
    fi
done
MOCK_EMBEDDING="${MOCK_EMBEDDING}]"

echo "✅ Created 128-dimensional embedding"
echo ""

# Step 2: Register face with UserRegistry (if reachable)
if [ "$SKIP_USER_REGISTRY" = false ]; then
    echo "Step 2: Registering face with UserRegistry..."

    REGISTER_PAYLOAD=$(cat <<EOF
{
  "embedding": ${MOCK_EMBEDDING},
  "confidence_score": 0.92,
  "source": "mediapipe",
  "snapshot_url": null,
  "location_hint": "Test Location",
  "existing_user_id": null
}
EOF
)

    REGISTER_RESPONSE=$(curl -s --max-time 10 -w "\n%{http_code}" \
      -X POST "${USER_REGISTRY_HOST}:${USER_REGISTRY_PORT}/faces/register" \
      -H "Content-Type: application/json" \
      -d "${REGISTER_PAYLOAD}")

    HTTP_CODE=$(echo "$REGISTER_RESPONSE" | tail -n1)
    REGISTER_BODY=$(echo "$REGISTER_RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
        echo "❌ FAILED: UserRegistry registration (HTTP ${HTTP_CODE})"
        echo "Response: ${REGISTER_BODY}"
        exit 1
    fi

    USER_ID=$(echo "$REGISTER_BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('data', {}).get('user_id', ''))" 2>/dev/null || echo "$REGISTER_BODY" | grep -o '"user_id":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$USER_ID" ]; then
        echo "❌ FAILED: Could not extract user_id"
        echo "Response: ${REGISTER_BODY}"
        exit 1
    fi

    echo "✅ Face registered successfully!"
    echo "   User ID: ${USER_ID}"
    echo ""
else
    echo "Step 2: SKIPPED (UserRegistry not reachable)"
    echo "   Using mock user_id: ${USER_ID}"
    echo ""
fi

# Step 3: Register profile with OpenResponses
echo "Step 3: Registering profile with OpenResponses (stage: register)..."

OPENRESPONSES_PAYLOAD=$(cat <<EOF
{
  "source": "visionclaw",
  "stage": "register",
  "userId": "${USER_ID}",
  "profile": {
    "name": null,
    "role": null,
    "key_skills": null,
    "interests": null,
    "notes": "Test registration via mock flow",
    "metadata": {
      "source": "test-script",
      "registered_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S")"
    }
  }
}
EOF
)

OPENRESPONSES_RESPONSE=$(curl -s --max-time 30 -w "\n%{http_code}" \
  -X POST "${OPENRESPONSES_HOST}:${OPENRESPONSES_PORT}/v1/responses" \
  -H "Authorization: Bearer ${BEARER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${OPENRESPONSES_PAYLOAD}")

HTTP_CODE=$(echo "$OPENRESPONSES_RESPONSE" | tail -n1)
OPENRESPONSES_BODY=$(echo "$OPENRESPONSES_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ FAILED: OpenResponses registration (HTTP ${HTTP_CODE})"
    echo "Response: ${OPENRESPONSES_BODY}"
    echo ""
    echo "Possible causes:"
    echo "  - OpenResponses API endpoint not configured"
    echo "  - Backend skill missing or misconfigured"
    echo "  - Invalid bearer token"
    echo "  - Stage 'register' not implemented"
    exit 1
fi

echo "✅ Profile registered successfully!"
echo "   Welcome Message:"
echo "   ┌─────────────────────────────────────────"
echo "   │ ${OPENRESPONSES_BODY}"
echo "   └─────────────────────────────────────────"
echo ""

# Step 4: Verify context fetch
echo "Step 4: Verifying context retrieval (stage: fetch)..."

FETCH_PAYLOAD=$(cat <<EOF
{
  "source": "visionclaw",
  "stage": "fetch",
  "userId": "${USER_ID}"
}
EOF
)

FETCH_RESPONSE=$(curl -s --max-time 30 -w "\n%{http_code}" \
  -X POST "${OPENRESPONSES_HOST}:${OPENRESPONSES_PORT}/v1/responses" \
  -H "Authorization: Bearer ${BEARER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${FETCH_PAYLOAD}")

HTTP_CODE=$(echo "$FETCH_RESPONSE" | tail -n1)
FETCH_BODY=$(echo "$FETCH_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
    echo "⚠️  WARNING: Context fetch failed (HTTP ${HTTP_CODE})"
    echo "   Response: ${FETCH_BODY}"
    echo "   This might be expected for a newly registered user"
else
    echo "✅ Context retrieved successfully!"
    echo "   Context:"
    echo "   ┌─────────────────────────────────────────"
    echo "   │ ${FETCH_BODY}"
    echo "   └─────────────────────────────────────────"
fi

echo ""

# Summary
echo "=== Test Complete ==="
echo ""
echo "Summary:"
if [ "$SKIP_USER_REGISTRY" = false ]; then
    echo "- UserRegistry: ✅ Face registered (ID: ${USER_ID})"
else
    echo "- UserRegistry: ⏭️  SKIPPED (service not reachable)"
fi
echo "- OpenResponses: ✅ Profile registered with welcome message"
if [ "$HTTP_CODE" = "200" ]; then
    echo "- OpenResponses: ✅ Context retrieval working"
else
    echo "- OpenResponses: ⚠️  Context retrieval (check logs)"
fi
echo ""

if [ "$SKIP_USER_REGISTRY" = false ]; then
    echo "To test the update stage, run:"
    echo "  curl -X POST ${OPENRESPONSES_HOST}:${OPENRESPONSES_PORT}/v1/responses \\"
    echo "    -H \"Authorization: Bearer ${BEARER_TOKEN}\" \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"source\":\"visionclaw\",\"stage\":\"update\",\"userId\":\"${USER_ID}\",\"chatTranscript\":\"Hello, I am Naveen. I love photography.\"}'"
fi
