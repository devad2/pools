#!/bin/bash

echo "🚀 Starting Poolside Platform MVP"
echo "================================"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Clean up any existing containers
echo "🧹 Cleaning up existing containers..."
docker-compose down -v 2>/dev/null || true

# Build and start services
echo "🔨 Building and starting services..."
docker-compose up -d

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
sleep 10

# Check service health
echo "🏥 Checking service health..."
docker-compose ps

# Test the API
echo "🧪 Testing API endpoints..."
sleep 5

# Test hello world endpoint
echo "📡 Testing hello world endpoint:"
curl -s http://localhost:3000/hello | jq '.' || echo "API not ready yet"

echo ""
echo "✅ Platform is running!"
echo ""
echo "📌 Available Services:"
echo "   - API (PostgREST): http://localhost:3000"
echo "   - PostgreSQL: localhost:5432"
echo ""
echo "📊 Useful API Endpoints:"
echo "   - GET  /hello - Hello world message"
echo "   - GET  /messages - All messages"
echo "   - GET  /rag_documents - RAG documents"
echo "   - POST /rpc/search_documents - Search with RAG"
echo "   - POST /rpc/schedule_training - Schedule training job"
echo "   - GET  /training_jobs - View training jobs"
echo "   - GET  /model_metrics - Model metrics"
echo ""
echo "🔄 Background Jobs (pg_cron):"
echo "   - Hourly: Process training jobs"
echo "   - Every 30m: Generate embeddings"
echo "   - Daily: Clean up old metrics"
echo "   - Weekly: Auto fine-tune model"
echo ""
echo "🛑 To stop: ./stop.sh"
echo "📜 To view logs: docker-compose logs -f [service-name]"
