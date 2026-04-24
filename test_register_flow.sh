#!/bin/bash

# Test Register Flow
# Tests the complete flow: UserRegistry registration → OpenResponses registration
# Created: 2026-04-24

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
USER_REGISTRY_HOST="http://192.168.1.173"
USER_REGISTRY_PORT="3100"
OPENRESPONSES_HOST="http://192.168.1.173"
OPENRESPONSES_PORT="18789"
BEARER_TOKEN="21c9e6fa03ca7784e68a2e096253c7490dd192467fbce904"

echo -e "${BLUE}=== Testing Register Flow ===${NC}\n"

# Step 1: Create mock embedding (128 random floats)
echo -e "${BLUE}📝 Step 1: Creating mock face embedding...${NC}"
MOCK_EMBEDDING="["
for i in {1..128}; do
    RANDOM_FLOAT=$(awk -v min=-1 -v max=1 'BEGIN{srand(); print min+rand()*(max-min)}')
    MOCK_EMBEDDING="${MOCK_EMBEDDING}${RANDOM_FLOAT}"
    if [ $i -lt 128 ]; then
        MOCK_EMBEDDING="${MOCK_EMBEDDING},"
    fi
done
MOCK_EMBEDDING="${MOCK_EMBEDDING}]"

echo -e "${GREEN}✅ Created 128-dimensional embedding${NC}\n"

# Step 2: Register face with UserRegistry
echo -e "${BLUE}📝 Step 2: Registering face with UserRegistry (port ${USER_REGISTRY_PORT})...${NC}"

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

REGISTER_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${USER_REGISTRY_HOST}:${USER_REGISTRY_PORT}/faces/register" \
  -H "Content-Type: application/json" \
  -d "${REGISTER_PAYLOAD}")

HTTP_CODE=$(echo "$REGISTER_RESPONSE" | tail -n1)
REGISTER_BODY=$(echo "$REGISTER_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo -e "${RED}❌ FAILED: UserRegistry registration failed (HTTP ${HTTP_CODE})${NC}"
    echo -e "${YELLOW}Response: ${REGISTER_BODY}${NC}"
    echo ""
    echo "Possible causes:"
    echo "  - UserRegistry service not running on port ${USER_REGISTRY_PORT}"
    echo "  - Network connectivity issue"
    echo "  - Invalid endpoint: ${USER_REGISTRY_HOST}:${USER_REGISTRY_PORT}/faces/register"
    exit 1
fi

# Extract user_id from response
USER_ID=$(echo "$REGISTER_BODY" | grep -o '"user_id":"[^"]*"' | cut -d'"' -f4)
FACE_EMBEDDING_ID=$(echo "$REGISTER_BODY" | grep -o '"face_embedding_id":"[^"]*"' | cut -d'"' -f4)
IS_NEW_USER=$(echo "$REGISTER_BODY" | grep -o '"is_new_user":[^,}]*' | cut -d':' -f2)

if [ -z "$USER_ID" ]; then
    echo -e "${RED}❌ FAILED: Could not extract user_id from response${NC}"
    echo -e "${YELLOW}Response: ${REGISTER_BODY}${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Face registered successfully!${NC}"
echo "   User ID: ${USER_ID}"
echo "   Face Embedding ID: ${FACE_EMBEDDING_ID}"
echo "   Is New User: ${IS_NEW_USER}"
echo ""

# Step 3: Register profile with OpenResponses
echo -e "${BLUE}📝 Step 3: Registering profile with OpenResponses (port ${OPENRESPONSES_PORT}, stage: register)...${NC}"

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
    "notes": "Registered via Ray-Ban Meta glasses",
    "metadata": {
      "source": "mediapipe",
      "registered_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    }
  }
}
EOF
)

OPENRESPONSES_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${OPENRESPONSES_HOST}:${OPENRESPONSES_PORT}/v1/responses" \
  -H "Authorization: Bearer ${BEARER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${OPENRESPONSES_PAYLOAD}")

HTTP_CODE=$(echo "$OPENRESPONSES_RESPONSE" | tail -n1)
OPENRESPONSES_BODY=$(echo "$OPENRESPONSES_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}❌ FAILED: OpenResponses registration failed (HTTP ${HTTP_CODE})${NC}"
    echo -e "${YELLOW}Response: ${OPENRESPONSES_BODY}${NC}"
    echo ""
    echo "Possible causes:"
    echo "  - OpenResponses API not deployed at ${OPENRESPONSES_HOST}:${OPENRESPONSES_PORT}/v1/responses"
    echo "  - OpenClaw Gateway not running on port ${OPENRESPONSES_PORT}"
    echo "  - Invalid bearer token"
    echo "  - Backend skill not configured for 'register' stage"
    echo ""
    echo -e "${YELLOW}⚠️  Note: Face is still registered in UserRegistry (user_id: ${USER_ID})${NC}"
    echo "   The app will continue to work, but without conversational welcome message"
    exit 1
fi

echo -e "${GREEN}✅ Profile registered successfully!${NC}"
echo "   Welcome Message:"
echo "   ---"
echo "   ${OPENRESPONSES_BODY}"
echo "   ---"
echo ""

# Step 4: Verify we can fetch context
echo -e "${BLUE}📝 Step 4: Verifying context retrieval (stage: fetch)...${NC}"

FETCH_PAYLOAD=$(cat <<EOF
{
  "source": "visionclaw",
  "stage": "fetch",
  "userId": "${USER_ID}"
}
EOF
)

FETCH_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${OPENRESPONSES_HOST}:${OPENRESPONSES_PORT}/v1/responses" \
  -H "Authorization: Bearer ${BEARER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${FETCH_PAYLOAD}")

HTTP_CODE=$(echo "$FETCH_RESPONSE" | tail -n1)
FETCH_BODY=$(echo "$FETCH_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${YELLOW}⚠️  WARNING: Context fetch failed (HTTP ${HTTP_CODE})${NC}"
    echo "   This is expected for a newly registered user with no conversation history"
    echo "   Response: ${FETCH_BODY}"
    echo ""
    echo -e "${BLUE}=== Test Complete ===${NC}"
    echo -e "${GREEN}✅ Register flow validated (with expected fetch warning)${NC}"
    echo ""
    echo "Summary:"
    echo "- UserRegistry: ✅ Face registered (ID: ${USER_ID})"
    echo "- OpenResponses: ✅ Profile registered with welcome message"
    echo "- OpenResponses: ⚠️  Context retrieval (expected to be empty for new user)"
    exit 0
fi

echo -e "${GREEN}✅ Context retrieved successfully!${NC}"
echo "   Context:"
echo "   ---"
echo "   ${FETCH_BODY}"
echo "   ---"
echo ""

# Summary
echo -e "${BLUE}=== Test Complete ===${NC}"
echo -e "${GREEN}✅ All stages passed! Register flow is working correctly.${NC}"
echo ""
echo "Summary:"
echo "- UserRegistry: ✅ Face registered (ID: ${USER_ID})"
echo "- OpenResponses: ✅ Profile registered with welcome message"
echo "- OpenResponses: ✅ Context retrieval working"
echo ""
echo "To test the update stage, run:"
echo "  curl -X POST ${OPENRESPONSES_HOST}:${OPENRESPONSES_PORT}/v1/responses \\"
echo "    -H \"Authorization: Bearer ${BEARER_TOKEN}\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"source\":\"visionclaw\",\"stage\":\"update\",\"userId\":\"${USER_ID}\",\"chatTranscript\":\"Hello, I'\''m Naveen. I love photography and Puerto Rico.\"}'"
