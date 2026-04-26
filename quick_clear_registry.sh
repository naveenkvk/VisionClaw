#!/bin/bash
#
# quick_clear_registry.sh
# Clears all data from the User Registry PostgreSQL database
#
# Usage: ./quick_clear_registry.sh
#

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Database Configuration
DB_HOST="${USER_REGISTRY_HOST:-localhost}"
DB_PORT="${USER_REGISTRY_PORT:-5432}"
DB_NAME="${USER_REGISTRY_DB:-user_registry}"
DB_USER="${USER_REGISTRY_USER:-postgres}"
DB_PASSWORD="${USER_REGISTRY_PASSWORD:-dev_password}"

# Try to auto-detect Docker container
DOCKER_CONTAINER=""
for pattern in "user-registry-postgres" "user_registry_postgres" "user-registry_postgres"; do
    found=$(docker ps --format '{{.Names}}' | grep -i "$pattern" | head -1 || true)
    if [ ! -z "$found" ]; then
        DOCKER_CONTAINER="$found"
        break
    fi
done

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   User Registry Database Cleaner${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Check if running in Docker or direct connection
USE_DOCKER=false
if [ ! -z "$DOCKER_CONTAINER" ]; then
    echo -e "${GREEN}✓${NC} Found Docker container: ${DOCKER_CONTAINER}"
    USE_DOCKER=true
else
    echo -e "${YELLOW}⚠${NC}  Docker container not found, using direct connection"
    echo -e "   Host: ${DB_HOST}:${DB_PORT}"
    echo -e "   Database: ${DB_NAME}"
    echo -e "   User: ${DB_USER}"
fi

echo ""
echo -e "${RED}⚠️  WARNING: This will permanently delete ALL data:${NC}"
echo ""
echo "   • All face embeddings"
echo "   • All user profiles"
echo "   • All conversation history"
echo ""
echo -e "${YELLOW}   This action CANNOT be undone!${NC}"
echo ""

# Require explicit confirmation
read -p "Type 'DELETE ALL DATA' to confirm: " confirm

if [ "$confirm" != "DELETE ALL DATA" ]; then
    echo ""
    echo -e "${YELLOW}✗ Aborted. No data was deleted.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Starting database cleanup...${NC}"
echo ""

# SQL commands to clear all tables (only existing tables)
SQL_COMMANDS="
-- Disable foreign key checks temporarily
SET session_replication_role = 'replica';

-- Clear all tables (preserving schema)
-- Only truncate if table exists
DO \$\$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'conversations') THEN
        TRUNCATE TABLE conversations CASCADE;
        RAISE NOTICE 'Cleared: conversations';
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'face_embeddings') THEN
        TRUNCATE TABLE face_embeddings CASCADE;
        RAISE NOTICE 'Cleared: face_embeddings';
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'social_profiles') THEN
        TRUNCATE TABLE social_profiles CASCADE;
        RAISE NOTICE 'Cleared: social_profiles';
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'users') THEN
        TRUNCATE TABLE users CASCADE;
        RAISE NOTICE 'Cleared: users';
    END IF;
END \$\$;

-- Re-enable foreign key checks
SET session_replication_role = 'origin';

-- Vacuum to reclaim space
VACUUM ANALYZE;
"

# Execute SQL based on connection method
if [ "$USE_DOCKER" = true ]; then
    # Use Docker exec
    echo "Executing via Docker container..."
    docker exec -i "$DOCKER_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" 2>&1 <<EOF | grep -v "ivfflat index created with little data" | grep -v "This will cause low recall" | grep -v "Drop the index until"
$SQL_COMMANDS
EOF
    EXIT_CODE=${PIPESTATUS[0]}
else
    # Use psql direct connection
    echo "Executing via direct PostgreSQL connection..."
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" 2>&1 <<EOF | grep -v "ivfflat index created with little data" | grep -v "This will cause low recall" | grep -v "Drop the index until"
$SQL_COMMANDS
EOF
    EXIT_CODE=${PIPESTATUS[0]}
fi

echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ User Registry cleared successfully!${NC}"
    echo ""
    echo "Summary:"

    if [ "$USE_DOCKER" = true ]; then
        # Show counts via Docker (only for existing tables)
        echo ""
        docker exec -i "$DOCKER_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t <<EOF 2>/dev/null
SELECT 
    table_name,
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t.table_name) as exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t.table_name) > 0 
        THEN (SELECT COUNT(*)::text FROM "public"."' || t.table_name || '")
        ELSE 'N/A'
    END as rows
FROM (VALUES ('users'), ('face_embeddings'), ('conversations'), ('social_profiles')) AS t(table_name);
EOF

        # Simpler count query
        docker exec -i "$DOCKER_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" <<EOF 2>/dev/null
SELECT 
    'users' as table_name,
    COUNT(*) as rows_remaining,
    'Cleared ✓' as status
FROM users
WHERE EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'users')
UNION ALL
SELECT 
    'face_embeddings' as table_name,
    COUNT(*) as rows_remaining,
    'Cleared ✓' as status
FROM face_embeddings
WHERE EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'face_embeddings')
UNION ALL
SELECT 
    'conversations' as table_name,
    COUNT(*) as rows_remaining,
    'Cleared ✓' as status
FROM conversations
WHERE EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'conversations');
EOF
    else
        # Show counts via direct connection
        echo ""
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<EOF 2>/dev/null
SELECT 
    'users' as table_name,
    COUNT(*) as rows_remaining,
    'Cleared ✓' as status
FROM users
WHERE EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'users')
UNION ALL
SELECT 
    'face_embeddings' as table_name,
    COUNT(*) as rows_remaining,
    'Cleared ✓' as status
FROM face_embeddings
WHERE EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'face_embeddings')
UNION ALL
SELECT 
    'conversations' as table_name,
    COUNT(*) as rows_remaining,
    'Cleared ✓' as status
FROM conversations
WHERE EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'conversations');
EOF
    fi

    echo ""
    echo -e "${GREEN}All tables cleared. Database is ready for fresh data.${NC}"
    echo ""
else
    echo -e "${RED}❌ Failed to clear registry.${NC}"
    echo ""
    echo "Possible issues:"
    echo "  • Database connection failed"
    echo "  • Wrong credentials"
    echo "  • Tables don't exist yet"
    echo "  • Docker container not running"
    echo ""
    echo "Configuration used:"
    echo "  Host: $DB_HOST"
    echo "  Port: $DB_PORT"
    echo "  Database: $DB_NAME"
    echo "  User: $DB_USER"
    echo "  Docker: $USE_DOCKER"
    if [ "$USE_DOCKER" = true ]; then
        echo "  Container: $DOCKER_CONTAINER"
    fi
    echo ""
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
