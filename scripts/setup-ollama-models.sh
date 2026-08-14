#!/bin/bash
# Setup script for pulling required Ollama models for Prescient gem

set -e

OLLAMA_URL=${OLLAMA_URL:-"http://localhost:11434"}
EMBEDDING_MODEL=${OLLAMA_EMBEDDING_MODEL:-"nomic-embed-text"}
CHAT_MODEL=${OLLAMA_CHAT_MODEL:-"llama3.2:3b"}

echo "🚀 Setting up Ollama models for Prescient gem..."
echo "Ollama URL: $OLLAMA_URL"

# Function to check if Ollama is ready
wait_for_ollama() {
    echo "⏳ Waiting for Ollama to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
            echo "✅ Ollama is ready!"
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts - Ollama not ready yet..."
        sleep 2
        ((attempt++))
    done
    
    echo "❌ Ollama failed to start within expected time"
    exit 1
}

# Function to pull a model
pull_model() {
    local model_name=$1
    echo "📦 Pulling model: $model_name"
    
    if curl -s -X POST "$OLLAMA_URL/api/pull" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$model_name\"}" | grep -q "success"; then
        echo "✅ Successfully pulled $model_name"
    else
        echo "⚠️  Model pull initiated for $model_name (this may take a while)"
        # Wait a bit and check if model appears in list
        sleep 5
    fi
}

# Function to list available models
list_models() {
    echo "📋 Available models:"
    curl -s "$OLLAMA_URL/api/tags" | jq -r '.models[]?.name // empty' 2>/dev/null || echo "Unable to list models"
}

# Main execution
main() {
    wait_for_ollama
    
    echo "🔧 Current models:"
    list_models
    
    echo "📥 Pulling required models..."
    pull_model "$EMBEDDING_MODEL"
    pull_model "$CHAT_MODEL"
    
    echo "✨ Model setup complete!"
    echo "📋 Final model list:"
    list_models
    
    echo ""
    echo "🎉 Ollama is ready for use with Prescient gem!"
    echo "💡 You can now run the examples with:"
    echo "   OLLAMA_URL=$OLLAMA_URL ruby examples/custom_contexts.rb"
}

main "$@"
