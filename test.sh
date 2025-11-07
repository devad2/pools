#!/bin/bash

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

echo "Testing Simple RAG System"
echo "========================="
echo ""

# Use environment variables or defaults
API_URL="${API_URL:-http://localhost:${POSTGREST_PORT:-3000}}"
LLM_ENDPOINT="${LLM_ENDPOINT:-http://localhost:8000}"
LLM_MODEL="${LLM_MODEL:-microsoft/Phi-3-mini-4k-instruct}"
LLM_API_KEY="${LLM_API_KEY:-}"

echo "Configuration:"
echo "  API URL: $API_URL"
echo "  LLM Endpoint: $LLM_ENDPOINT"
echo "  LLM Model: $LLM_MODEL"
echo ""

# Function to pretty print JSON
pretty_json() {
    echo "$1" | jq '.' 2>/dev/null || echo "$1"
}

# Wait for API to be ready
echo "Waiting for PostgREST API to be ready..."
until curl -s $API_URL/hello > /dev/null 2>&1; do
    sleep 1
done
echo "✓ PostgREST API is ready"

# Check if LLM endpoint is available
echo "Checking LLM endpoint availability..."
if curl -s "$LLM_ENDPOINT/health" > /dev/null 2>&1 || curl -s "$LLM_ENDPOINT/v1/models" > /dev/null 2>&1; then
    echo "✓ LLM endpoint is ready"
else
    echo "⚠ Warning: LLM endpoint not responding. LLM tests may fail."
    echo "  Make sure your LLM server is running at: $LLM_ENDPOINT"
fi

echo ""
echo "=========================================="
echo "Test 1: Hello World"
echo "=========================================="
echo "GET $API_URL/hello"
response=$(curl -s $API_URL/hello)
pretty_json "$response"

echo ""
echo "=========================================="
echo "Test 2: List all RAG documents"
echo "=========================================="
echo "GET $API_URL/rag_documents"
response=$(curl -s $API_URL/rag_documents)
pretty_json "$response"

echo ""
echo "=========================================="
echo "Test 3: Search for documents about 'python'"
echo "=========================================="
echo "POST $API_URL/rpc/search_documents"
response=$(curl -s -X POST $API_URL/rpc/search_documents \
    -H "Content-Type: application/json" \
    -d '{
        "query_text": "python programming",
        "limit_count": 3
    }')
pretty_json "$response"

echo ""
echo "=========================================="
echo "Test 4: Get RAG query with prompt"
echo "=========================================="
echo "POST $API_URL/rpc/rag_query"
response=$(curl -s -X POST $API_URL/rpc/rag_query \
    -H "Content-Type: application/json" \
    -d '{
        "user_query": "How does Python work?"
    }')
pretty_json "$response"

# Extract the prompt for the next test
prompt=$(echo "$response" | jq -r '.[0].prompt // empty' 2>/dev/null)

echo ""
echo "=========================================="
echo "Test 5: Call LLM with the generated prompt"
echo "=========================================="
echo "POST $LLM_ENDPOINT/v1/chat/completions"

if [ -n "$prompt" ]; then
    if [ -n "$LLM_API_KEY" ]; then
        response=$(curl -s -X POST "$LLM_ENDPOINT/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $LLM_API_KEY" \
            -d "{
                \"model\": \"$LLM_MODEL\",
                \"messages\": [
                    {
                        \"role\": \"user\",
                        \"content\": $(echo "$prompt" | jq -R -s .)
                    }
                ],
                \"max_tokens\": 200,
                \"temperature\": 0.7
            }")
    else
        response=$(curl -s -X POST "$LLM_ENDPOINT/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"$LLM_MODEL\",
                \"messages\": [
                    {
                        \"role\": \"user\",
                        \"content\": $(echo "$prompt" | jq -R -s .)
                    }
                ],
                \"max_tokens\": 200,
                \"temperature\": 0.7
            }")
    fi
    pretty_json "$response"
else
    echo "⚠ No prompt generated, testing with simple prompt instead"
    if [ -n "$LLM_API_KEY" ]; then
        response=$(curl -s -X POST "$LLM_ENDPOINT/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $LLM_API_KEY" \
            -d "{
                \"model\": \"$LLM_MODEL\",
                \"messages\": [
                    {
                        \"role\": \"user\",
                        \"content\": \"What is Python?\"
                    }
                ]
            }")
    else
        response=$(curl -s -X POST "$LLM_ENDPOINT/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"$LLM_MODEL\",
                \"messages\": [
                    {
                        \"role\": \"user\",
                        \"content\": \"What is Python?\"
                    }
                ]
            }")
    fi
    pretty_json "$response"
fi

echo ""
echo "=========================================="
echo "Test 6: Add a new document"
echo "=========================================="
echo "POST $API_URL/rag_documents"
response=$(curl -s -X POST $API_URL/rag_documents \
    -H "Content-Type: application/json" \
    -d '{
        "title": "Rust Programming",
        "content": "Rust is a systems programming language focused on safety, speed, and concurrency.",
        "metadata": {"category": "programming"}
    }')
pretty_json "$response"

echo ""
echo "=========================================="
echo "Test 7: Search for the new document"
echo "=========================================="
echo "POST $API_URL/rpc/search_documents"
response=$(curl -s -X POST $API_URL/rpc/search_documents \
    -H "Content-Type: application/json" \
    -d '{
        "query_text": "rust programming",
        "limit_count": 3
    }')
pretty_json "$response"

echo ""
echo "=========================================="
echo "✓ All tests completed!"
echo "=========================================="
