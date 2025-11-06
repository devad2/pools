#!/bin/bash

echo "🛑 Stopping Poolside Platform"
echo "============================="

docker-compose down

echo "✅ Platform stopped successfully"
echo ""
echo "To remove all data volumes, run:"
echo "docker-compose down -v"
