#!/bin/bash

echo "🧪 Testing Poolside Platform API"
echo "================================"

API_URL="http://localhost:3000"

# Function to pretty print JSON
pretty_json() {
    echo "$1" | jq '.' 2>/dev/null || echo "$1"
}

# Wait for API to be ready
echo "⏳ Waiting for API to be ready..."
until curl -s $API_URL/hello > /dev/null 2>&1; do
    sleep 1
done

echo ""
echo "1️⃣  Testing Hello World endpoint:"
echo "   GET $API_URL/hello"
response=$(curl -s $API_URL/hello)
pretty_json "$response"

echo ""
echo "2️⃣  Testing Messages endpoint:"
echo "   GET $API_URL/messages"
response=$(curl -s $API_URL/messages)
pretty_json "$response"

echo ""
echo "3️⃣  Adding a conversation:"
echo "   POST $API_URL/conversations"
response=$(curl -s -X POST $API_URL/conversations \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": 1,
        "input_text": "How do I implement a REST API?",
        "output_text": "To implement a REST API, you need to follow RESTful principles...",
        "feedback_score": 5
    }')
pretty_json "$response"

echo ""
echo "4️⃣  Adding a RAG document:"
echo "   POST $API_URL/rag_documents"
response=$(curl -s -X POST $API_URL/rag_documents \
    -H "Content-Type: application/json" \
    -d '{
        "title": "REST API Best Practices",
        "content": "When building REST APIs, consider these principles: statelessness, resource-based URLs, HTTP methods...",
        "metadata": {"category": "documentation", "version": "1.0"}
    }')
pretty_json "$response"

echo ""
echo "5️⃣  Scheduling a training job:"
echo "   POST $API_URL/rpc/schedule_training"
response=$(curl -s -X POST $API_URL/rpc/schedule_training \
    -H "Content-Type: application/json" \
    -d '{
        "job_type": "embed_documents",
        "params": {"batch_size": 10}
    }')
pretty_json "$response"

echo ""
echo "6️⃣  Viewing training jobs:"
echo "   GET $API_URL/training_jobs"
response=$(curl -s "$API_URL/training_jobs?order=created_at.desc&limit=5")
pretty_json "$response"

echo ""
echo "7️⃣  Searching documents (RAG):"
echo "   POST $API_URL/rpc/search_documents"
response=$(curl -s -X POST $API_URL/rpc/search_documents \
    -H "Content-Type: application/json" \
    -d '{
        "query_text": "REST API",
        "limit_count": 3
    }')
pretty_json "$response"

echo ""
echo "✅ API tests completed!"
