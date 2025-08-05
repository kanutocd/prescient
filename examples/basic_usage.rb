#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Basic usage of the Prescient gem
# This example shows how to use different providers for embeddings and text generation

require_relative '../lib/prescient'

# Example 1: Using default Ollama provider
puts "=== Example 1: Default Ollama Provider ==="

begin
  # Create client using default provider (Ollama)
  client = Prescient.client
  
  # Check if provider is available
  if client.available?
    puts "✅ Ollama is available"
    
    # Generate embedding
    text = "Ruby is a dynamic programming language"
    embedding = client.generate_embedding(text)
    puts "📊 Generated embedding with #{embedding.length} dimensions"
    
    # Generate response
    response = client.generate_response("What is Ruby programming language?")
    puts "🤖 AI Response:"
    puts response[:response]
    puts "📈 Model: #{response[:model]}, Provider: #{response[:provider]}"
  else
    puts "❌ Ollama is not available"
  end
rescue Prescient::Error => e
  puts "❌ Error with Ollama: #{e.message}"
end

# Example 2: Context-Aware Generation
puts "\n=== Example 2: Context-Aware Generation ==="

begin
  client = Prescient.client
  
  # Simulate context items (would come from vector search in real applications)
  context_items = [
    {
      'title' => 'Network Configuration Guide',
      'content' => 'Network propagation typically takes 24-48 hours to complete globally. During this time, changes may not be visible from all locations.'
    },
    {
      'title' => 'Technical FAQ',
      'content' => 'DNS changes can take anywhere from a few minutes to 48 hours to propagate worldwide due to caching mechanisms.'
    }
  ]
  
  query = "How long does network propagation take?"
  response = client.generate_response(query, context_items)
  
  puts "🔍 Query: #{query}"
  puts "📋 Context: #{context_items.length} items"
  puts "🤖 AI Response:"
  puts response[:response]
  
rescue Prescient::Error => e
  puts "❌ Error with context example: #{e.message}"
end

# Example 3: Provider comparison (if multiple providers configured)
puts "\n=== Example 3: Provider Health Check ==="

providers = [:ollama, :anthropic, :openai, :huggingface]

providers.each do |provider_name|
  begin
    health = Prescient.health_check(provider: provider_name)
    status_emoji = health[:status] == 'healthy' ? '✅' : '❌'
    puts "#{status_emoji} #{provider_name.to_s.capitalize}: #{health[:status]}"
    
    if health[:ready]
      puts "  Ready: #{health[:ready]}"
    end
    
    if health[:models_available]
      puts "  Models: #{health[:models_available].first(3).join(', ')}#{'...' if health[:models_available].length > 3}"
    end
    
  rescue Prescient::Error => e
    puts "❌ #{provider_name.to_s.capitalize}: #{e.message}"
  end
end

# Example 4: Error handling
puts "\n=== Example 4: Error Handling ==="

begin
  # Try to use a provider that might not be configured
  client = Prescient.client(:nonexistent)
rescue Prescient::Error => e
  puts "❌ Expected error: #{e.message}"
end

# Example 5: Custom configuration
puts "\n=== Example 5: Custom Configuration ==="

Prescient.configure do |config|
  config.timeout = 30
  config.retry_attempts = 2
  config.retry_delay = 0.5
  
  # Add custom Ollama configuration
  config.add_provider(:custom_ollama, Prescient::Provider::Ollama,
    url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
    embedding_model: 'nomic-embed-text',
    chat_model: 'llama3.1:8b',
    timeout: 60
  )
end

puts "⚙️  Custom configuration applied"
puts "   Timeout: #{Prescient.configuration.timeout}s"
puts "   Retry attempts: #{Prescient.configuration.retry_attempts}"
puts "   Providers: #{Prescient.configuration.providers.keys.join(', ')}"

puts "\n🎉 Examples completed!"