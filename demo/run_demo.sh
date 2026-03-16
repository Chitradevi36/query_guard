#!/bin/bash
# QueryGuard Demo Runner
# Quick script to set up and run the demo

set -e

echo "🚀 QueryGuard Demo Runner"
echo "════════════════════════════════════════"

# Configuration
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATABASE_URL="${DATABASE_URL:-postgres://postgres:postgres@localhost:5432/queryguard_demo}"

echo "📁 Demo directory: $DEMO_DIR"
echo "🗄️  Database: $DATABASE_URL"
echo ""

# Step 1: Install dependencies
echo "📦 Installing dependencies..."
cd "$DEMO_DIR"
bundle install --quiet

# Step 2: Setup database (only if Postgres is available)
if command -v psql &> /dev/null; then
    echo "🗄️  Setting up database..."
    export DATABASE_URL=$DATABASE_URL
    bundle exec rake db:drop 2>/dev/null || true
    bundle exec rake db:create
    bundle exec rake db:migrate
    echo "✅ Database ready"
else
    echo "⚠️  PostgreSQL not found. Skipping database setup."
    echo "   Install PostgreSQL or set DATABASE_URL to a valid database"
fi

echo ""
echo "════════════════════════════════════════"
echo "📊 Running QueryGuard Analysis"
echo "════════════════════════════════════════"
echo ""

# Step 3: Run QueryGuard analysis
echo "Analyzing migrations..."
bundle exec queryguard analyze db/migrate

echo ""
echo "════════════════════════════════════════"
echo "✨ Demo Complete!"
echo "════════════════════════════════════════"
echo ""
echo "📋 Additional commands:"
echo ""
echo "  # Verbose analysis with recommendations"
echo "  bundle exec queryguard analyze db/migrate --verbose"
echo ""
echo "  # Check with error threshold (should fail due to CRITICAL finding)"
echo "  bundle exec queryguard check db/migrate --threshold critical"
echo ""
echo "  # Get JSON output"
echo "  bundle exec queryguard analyze db/migrate --format json"
echo ""
echo "  # Pretty print JSON"
echo "  bundle exec queryguard analyze db/migrate --format json | jq"
echo ""
echo "📚 For more info, see demo/README.md"
echo ""
