#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Custom prompt templates with the Prescient gem
# This example shows how to customize AI assistant behavior with custom prompts

require_relative '../lib/prescient'

puts "=== Custom Prompt Templates Example ==="

# Example 1: Customer Service Assistant
puts "\n--- Example 1: Customer Service Assistant ---"

Prescient.configure do |config|
  config.add_provider(:customer_service, Prescient::Provider::Ollama,
    url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
    embedding_model: 'nomic-embed-text',
    chat_model: 'llama3.1:8b',
    prompt_templates: {
      system_prompt: 'You are a friendly customer service representative. Be helpful, empathetic, and professional.',
      no_context_template: <<~TEMPLATE.strip,
        %{system_prompt}

        Customer Question: %{query}

        Please provide a helpful and professional response.
      TEMPLATE
      with_context_template: <<~TEMPLATE.strip
        %{system_prompt} Use the following company information to help answer the customer's question.

        Company Information:
        %{context}

        Customer Question: %{query}

        Please provide a helpful response based on our company policies and information above.
      TEMPLATE
    }
  )
end

begin
  client = Prescient.client(:customer_service)
  
  if client.available?
    # Test without context
    response = client.generate_response("What's your return policy?")
    puts "🎧 Customer Service Response:"
    puts response[:response]
    
    # Test with context
    context = [
      {
        'title' => 'Return Policy',
        'content' => 'We offer 30-day returns on all items in original condition with receipt.'
      }
    ]
    
    response = client.generate_response("What's your return policy?", context)
    puts "\n🎧 With Policy Context:"
    puts response[:response]
  else
    puts "❌ Customer service provider not available"
  end
rescue Prescient::Error => e
  puts "❌ Error: #{e.message}"
end

# Example 2: Technical Documentation Assistant
puts "\n--- Example 2: Technical Documentation Assistant ---"

Prescient.configure do |config|
  config.add_provider(:tech_docs, Prescient::Provider::Ollama,
    url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
    embedding_model: 'nomic-embed-text',
    chat_model: 'llama3.1:8b',
    prompt_templates: {
      system_prompt: 'You are a technical documentation assistant. Provide clear, accurate, and detailed technical explanations with code examples when relevant.',
      no_context_template: <<~TEMPLATE.strip,
        %{system_prompt}

        Technical Question: %{query}

        Please provide a detailed technical explanation with examples if applicable.
      TEMPLATE
      with_context_template: <<~TEMPLATE.strip
        %{system_prompt}

        Documentation Context:
        %{context}

        Technical Question: %{query}

        Based on the documentation above, provide a comprehensive technical answer with relevant code examples.
      TEMPLATE
    }
  )
end

begin
  client = Prescient.client(:tech_docs)
  
  if client.available?
    context = [
      {
        'title' => 'API Authentication',
        'content' => 'Use Bearer tokens in the Authorization header: Authorization: Bearer your_token_here'
      }
    ]
    
    response = client.generate_response("How do I authenticate with the API?", context)
    puts "💻 Technical Documentation Response:"
    puts response[:response]
  else
    puts "❌ Technical docs provider not available"
  end
rescue Prescient::Error => e
  puts "❌ Error: #{e.message}"
end

# Example 3: Creative Writing Assistant
puts "\n--- Example 3: Creative Writing Assistant ---"

Prescient.configure do |config|
  config.add_provider(:creative, Prescient::Provider::Ollama,
    url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
    embedding_model: 'nomic-embed-text',
    chat_model: 'llama3.1:8b',
    prompt_templates: {
      system_prompt: 'You are a creative writing assistant. Help with storytelling, character development, and creative inspiration. Be imaginative and encouraging.',
      no_context_template: <<~TEMPLATE.strip,
        %{system_prompt}

        Writing Request: %{query}

        Let's create something amazing together!
      TEMPLATE
      with_context_template: <<~TEMPLATE.strip
        %{system_prompt}

        Story Elements:
        %{context}

        Writing Request: %{query}

        Use the story elements above to craft your creative response.
      TEMPLATE
    }
  )
end

begin
  client = Prescient.client(:creative)
  
  if client.available?
    context = [
      {
        'title' => 'Setting',
        'content' => 'A mysterious library that exists between dimensions, where books write themselves'
      },
      {
        'title' => 'Character',
        'content' => 'Maya, a young librarian who can read the thoughts of books'
      }
    ]
    
    response = client.generate_response("Write an opening paragraph for this story", context)
    puts "✍️  Creative Writing Response:"
    puts response[:response]
  else
    puts "❌ Creative provider not available"
  end
rescue Prescient::Error => e
  puts "❌ Error: #{e.message}"
end

# Example 4: Default prompt override
puts "\n--- Example 4: Override Default Prompts ---"

# You can also override the default prompts for any provider
Prescient.configure do |config|
  config.add_provider(:custom_default, Prescient::Provider::Ollama,
    url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
    embedding_model: 'nomic-embed-text',
    chat_model: 'llama3.1:8b',
    prompt_templates: {
      # Only override the system prompt, keep default templates
      system_prompt: 'You are Sherlock Holmes. Approach every question with deductive reasoning and attention to detail.'
    }
  )
end

begin
  client = Prescient.client(:custom_default)
  
  if client.available?
    response = client.generate_response("How should I approach solving a complex problem?")
    puts "🔍 Sherlock Holmes Response:"
    puts response[:response]
  else
    puts "❌ Custom default provider not available"
  end
rescue Prescient::Error => e
  puts "❌ Error: #{e.message}"
end

puts "\n🎉 Custom prompt examples completed!"
puts "\n💡 Tips:"
puts "   - Use %{system_prompt}, %{query}, and %{context} placeholders in templates"
puts "   - Templates use Ruby's % string formatting"
puts "   - Override any or all template parts (system_prompt, no_context_template, with_context_template)"
puts "   - Each provider can have completely different prompt behavior"