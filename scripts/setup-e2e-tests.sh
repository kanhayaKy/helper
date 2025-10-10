#!/bin/bash

# Helper - E2E Testing Environment Setup Script
# This script sets up everything needed for E2E testing including Supabase, database migrations, and Playwright

set -e

start_time=$(date +%s)

# Logging functions
start_step() {
    echo "========================================================================"
    echo "▶️  $1"
    echo "========================================================================"
    STEP_START_TIME=$(date +%s)
}

end_step() {
    STEP_END_TIME=$(date +%s)
    ELAPSED_TIME=$((STEP_END_TIME - STEP_START_TIME))
    echo "✅ Done in ${ELAPSED_TIME}s"
    echo ""
}

echo "🎭 Setting up E2E Testing Environment for Helper"
echo "================================================"

if [ ! -f "package.json" ]; then
    echo "❌ Error: Please run this script from the root of the Helper project"
    exit 1
fi

echo "Current directory: $(pwd)"

if [ ! -f ".env.test" ]; then
    echo "⚠️ .env.test not found. Please create it from .env.local.sample."
    echo "📁 Files in current directory:"
    ls -la .env* 2>/dev/null || echo "No .env files found"
    exit 1
fi

echo "✅ .env.test found"

if [ "$CI" != "true" ]; then
    if [ ! -f ".env.test.local" ]; then
        echo "📝 Creating .env.test.local from .env.test..."
        cp .env.test .env.test.local
        echo "✅ Created .env.test.local - you can customize it with local values if needed"
    else
        echo "✅ .env.test.local already exists"
    fi
fi

echo "🔧 Loading environment variables..."
set -o allexport
source .env.test
if [ "$CI" != "true" ] && [ -f ".env.test.local" ]; then
  source .env.test.local
fi
set +o allexport

CI="${CI:-false}"
echo "CI is set to $CI"

start_step "Ensuring no Supabase services are running"
pnpm run with-test-env pnpm supabase stop --no-backup 2>/dev/null || true
end_step

start_step "Cleaning up existing Supabase containers (if any)"
EXISTING_CONTAINERS=$(docker ps -a -q --filter "name=${SUPABASE_PROJECT_ID}" 2>/dev/null || true)
if [ ! -z "$EXISTING_CONTAINERS" ]; then
    echo "Found existing Supabase containers for project ${SUPABASE_PROJECT_ID}, cleaning up..."
    echo "Stopping containers..."
    docker stop $EXISTING_CONTAINERS || true
    echo "Removing containers..."
    docker rm $EXISTING_CONTAINERS || true
    echo "Existing containers cleaned up"
else
    echo "No existing Supabase containers found for project ${SUPABASE_PROJECT_ID}"
fi
end_step

start_step "Starting Supabase services"
if [ "$CI" = "true" ]; then
  echo "🪄 Using slim Supabase config for CI"
  export SUPABASE_CONFIG_PATH="./supabase/config.ci.toml"
fi
pnpm run with-test-env pnpm supabase start
end_step

echo "⏳ Waiting for Auth service to initialize..."
sleep 5

start_step "Resetting database"
pnpm run with-test-env pnpm supabase db reset
end_step

start_step "Applying database migrations"
pnpm run with-test-env drizzle-kit migrate --config ./db/drizzle.config.ts
end_step

if [ "$CI" != "true" ]; then
    start_step "Building packages"
    pnpm run-on-packages build
    end_step
else
    echo "⏭️  Skipping package builds in CI (built during pnpm install postinstall)"
fi

start_step "Seeding the database"
pnpm run with-test-env pnpm tsx --conditions=react-server ./db/seeds/seedDatabase.ts
end_step

if [ "$CI" != "true" ]; then
    start_step "Installing Playwright and dependencies"
    pnpm install
    end_step

    start_step "Installing Playwright browsers"
    pnpm run with-test-env playwright install --with-deps chromium
    end_step
else
    echo "⏭️  Skipping pnpm install and Playwright browser install in CI (handled by workflow)"
fi

echo ""
echo "🎉 E2E Testing Environment Setup Complete!"
echo ""
echo "📋 Next Steps:"
echo "   (optional) set PLAYWRIGHT_USE_PREBUILT=1 in .env.test.local to run e2e on production build"
echo ""
echo "   1. Run your tests using:"
echo "      ./scripts/e2e.sh                   # Run all tests"
echo "      ./scripts/e2e.sh playwright test tests/e2e/widget/widget-screenshot.spec.ts  # Interactive test runner"
echo ""
echo "   2. Or use pnpm commands directly:"
echo "      pnpm test:e2e                      # Run all tests"
echo "      pnpm test:e2e:debug                # Debug mode"
echo ""
echo "📖 Documentation:"
echo "   • Test documentation: tests/e2e/README.md"
echo "   • Playwright docs: https://playwright.dev/"
echo ""
echo "🐛 Troubleshooting:"
echo "   • Verify all services are running"
echo "   • Check test credentials in .env.test.local"
echo "   • Ensure Docker is running for Supabase"
echo ""
echo "Happy testing! 🚀"

end_time=$(date +%s)
total_elapsed_time=$((end_time - start_time))
echo "Total setup time: ${total_elapsed_time}s"