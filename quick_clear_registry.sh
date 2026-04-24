#!/bin/bash
# Quick User Registry Cleanup Script

echo "🔍 Finding postgres container..."
CONTAINER=$(docker ps --format '{{.Names}}' | grep -i postgres | head -n1)

if [ -z "$CONTAINER" ]; then
    echo "❌ No postgres container found. Is Docker running?"
    echo "Run: docker ps | grep postgres"
    exit 1
fi

echo "📦 Found container: $CONTAINER"
echo "⚠️  WARNING: This will delete ALL user data!"
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Aborted."
    exit 0
fi

echo "🗑️  Deleting all records..."
docker exec -i "$CONTAINER" psql -U postgres -d user_registry << SQL
TRUNCATE TABLE conversations CASCADE;
TRUNCATE TABLE face_embeddings CASCADE;
TRUNCATE TABLE users CASCADE;

SELECT 'users' as table_name, COUNT(*) as remaining_records FROM users
UNION ALL
SELECT 'face_embeddings', COUNT(*) FROM face_embeddings
UNION ALL
SELECT 'conversations', COUNT(*) FROM conversations;
SQL

echo "✅ Done! All User Registry data cleared."
