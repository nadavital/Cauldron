#!/bin/bash

# Deployment script for Cauldron API on corporate network
# This script uses npx with the public npm registry to bypass eBay's internal registry

echo "🚀 Cauldron API Deployment Script"
echo ""

# Check if we're in the vercel directory
if [ ! -f "package.json" ]; then
    echo "❌ Error: Please run this script from the vercel/ directory"
    exit 1
fi

# Command prefix for corporate network
VERCEL_CMD="npx --registry https://registry.npmjs.org vercel@latest"

# Check if this is the first run
if [ ! -d ".vercel" ]; then
    echo "📝 First time setup detected"
    echo ""
    echo "Step 1: Login to Vercel"
    echo "This will open your browser for authentication..."
    read -p "Press ENTER to continue..."
    $VERCEL_CMD login
    echo ""
fi

# Ask deployment type
echo "Choose deployment type:"
echo "1) Preview deployment (for testing)"
echo "2) Production deployment"
read -p "Enter choice (1 or 2): " choice

if [ "$choice" == "2" ]; then
    echo ""
    echo "🚀 Deploying to PRODUCTION..."
    $VERCEL_CMD --prod
else
    echo ""
    echo "🔍 Deploying to PREVIEW..."
    $VERCEL_CMD
fi

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Add environment variables in Vercel dashboard (if not done yet)"
echo "2. Update the baseURL in ExternalShareService.swift"
echo "3. Test the API endpoints"
