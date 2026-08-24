#!/bin/bash

echo "🔐 Extracting auth token from Flutter secure storage..."

# Try to get token from flutter secure storage
# This is a workaround - in production you'd use the actual token
TOKEN=$(flutter pub run test/get_token.dart 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
    echo "⚠️  Could not extract token automatically"
    echo ""
    echo "Please provide your auth token manually:"
    echo "1. Login to the app"
    echo "2. Check the logs for the token (look for 'Token: ...')"
    echo "3. Run: TOKEN='your_token_here' dart test/run_master_test.dart"
    echo ""
    echo "Or run the test directly with:"
    echo "  cd stocker && TOKEN='your_token_here' dart test/run_master_test.dart"
else
    echo "✅ Token found, running test..."
    cd stocker && TOKEN="$TOKEN" dart test/run_master_test.dart
fi
