#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Custom context configurations with the Prescient gem
# This example shows how to configure context formatting and embedding field extraction

require_relative '../lib/prescient'

puts "=== Custom Context Configurations Example ==="
puts "This example shows how to define your own context types and configurations."

# Example 1: E-commerce Product Catalog
puts "\n--- Example 1: E-commerce Product Catalog ---"

Prescient.configure do |config|
  config.add_provider(:ecommerce, Prescient::Provider::Ollama,
    url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
    embedding_model: 'nomic-embed-text',
    chat_model: 'llama3.1:8b',
    # Define your own context types - no hardcoded assumptions!
    context_configs: {
      'product' => {
        fields: %w[name description price category brand stock_count],
        format: '%{name} by %{brand}: %{description} - $%{price} (%{category}) [Stock: %{stock_count}]',
        embedding_fields: %w[name description category brand]  # Only these fields for embeddings
      },
      'review' => {
        fields: %w[product_name rating review_text reviewer_name date],
        format: '%{product_name} - %{rating}/5 stars by %{reviewer_name}: "%{review_text}"',
        embedding_fields: %w[product_name review_text]  # Exclude rating, reviewer, date from embeddings
      }
    },
    prompt_templates: {
      system_prompt: 'You are a helpful e-commerce assistant. Help customers find products and understand reviews.',
      with_context_template: <<~TEMPLATE.strip
        %{system_prompt}

        Product Catalog:
        %{context}

        Customer Question: %{query}

        Based on our product catalog above, provide helpful recommendations.
      TEMPLATE
    }
  )
end

begin
  client = Prescient.client(:ecommerce)
  
  if client.available?
    # Product catalog context
    products = [
      {
        'type' => 'product',
        'name' => 'UltraBook Pro',
        'description' => 'High-performance laptop with 16GB RAM and 512GB SSD',
        'price' => '1299.99',
        'category' => 'Laptops',
        'brand' => 'TechCorp',
        'stock_count' => '15'
      },
      {
        'type' => 'review',
        'product_name' => 'UltraBook Pro',
        'rating' => '5',
        'review_text' => 'Amazing performance and battery life. Perfect for development work.',
        'reviewer_name' => 'John D.',
        'date' => '2024-01-15'
      }
    ]
    
    response = client.generate_response("I need a laptop for programming work", products)
    puts "🛒 E-commerce Assistant Response:"
    puts response[:response]
  else
    puts "❌ E-commerce provider not available"
  end
rescue Prescient::Error => e
  puts "❌ Error: #{e.message}"
end

# Example 2: Healthcare Patient Records
puts "\n--- Example 2: Healthcare Patient Records ---"

Prescient.configure do |config|
  config.add_provider(:healthcare, Prescient::Provider::Ollama,
    url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
    embedding_model: 'nomic-embed-text',
    chat_model: 'llama3.1:8b',
    context_configs: {
      'patient' => {
        fields: %w[name age gender medical_conditions medications],
        format: 'Patient: %{name} (Age: %{age}, Gender: %{gender}) - Conditions: %{medical_conditions}, Medications: %{medications}',
        embedding_fields: %w[medical_conditions medications]
      },
      'appointment' => {
        fields: %w[patient_name date type notes doctor],
        format: 'Appointment for %{patient_name} on %{date} - %{type} with Dr. %{doctor}: %{notes}',
        embedding_fields: %w[type notes]
      }
    },
    prompt_templates: {
      system_prompt: 'You are a medical assistant AI. Provide helpful information while emphasizing the importance of consulting healthcare professionals.',
      with_context_template: <<~TEMPLATE.strip
        %{system_prompt}

        Patient Information:
        %{context}

        Medical Query: %{query}

        Based on the patient information, provide helpful guidance while emphasizing professional medical consultation.
      TEMPLATE
    }
  )
end

begin
  client = Prescient.client(:healthcare)
  
  if client.available?
    # Patient records context (anonymized example data)
    patient_data = [
      {
        'type' => 'patient',
        'name' => 'Patient A',
        'age' => '45',
        'gender' => 'Female',
        'medical_conditions' => 'Type 2 Diabetes, Hypertension',
        'medications' => 'Metformin, Lisinopril'
      },
      {
        'type' => 'appointment',
        'patient_name' => 'Patient A',
        'date' => '2024-01-20',
        'type' => 'Follow-up',
        'notes' => 'Blood sugar levels improving with current treatment',
        'doctor' => 'Johnson'
      }
    ]
    
    response = client.generate_response("What dietary considerations should be noted?", patient_data)
    puts "🏥 Healthcare Assistant Response:"
    puts response[:response]
  else
    puts "❌ Healthcare provider not available"
  end
rescue Prescient::Error => e
  puts "❌ Error: #{e.message}"
end

# Example 3: Software Project Management
puts "\n--- Example 3: Software Project Management ---"

Prescient.configure do |config|
  config.add_provider(:project_mgmt, Prescient::Provider::Ollama,
    url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
    embedding_model: 'nomic-embed-text',
    chat_model: 'llama3.1:8b',
    context_configs: {
      'issue' => {
        fields: %w[title description status priority assignee labels created_date],
        format: '#%{title} (%{status}) - Priority: %{priority}, Assigned: %{assignee} - %{description}',
        embedding_fields: %w[title description labels]
      },
      'pull_request' => {
        fields: %w[title description author status files_changed],
        format: 'PR: %{title} by %{author} (%{status}) - %{files_changed} files: %{description}',
        embedding_fields: %w[title description]
      },
      'team_member' => {
        fields: %w[name role skills experience projects],
        format: '%{name} - %{role} with %{experience} experience in %{skills}, working on: %{projects}',
        embedding_fields: %w[role skills projects]
      }
    },
    prompt_templates: {
      system_prompt: 'You are a software project management assistant. Help with planning, issue tracking, and team coordination.',
      with_context_template: <<~TEMPLATE.strip
        %{system_prompt}

        Project Context:
        %{context}

        Management Question: %{query}

        Based on the project information above, provide actionable project management advice.
      TEMPLATE
    }
  )
end

begin
  client = Prescient.client(:project_mgmt)
  
  if client.available?
    # Project management context
    project_data = [
      {
        'type' => 'issue',
        'title' => 'API Performance Optimization',
        'description' => 'Database queries are slow in user dashboard endpoint',
        'status' => 'In Progress',
        'priority' => 'High',
        'assignee' => 'Sarah Chen',
        'labels' => 'performance database api',
        'created_date' => '2024-01-18'
      },
      {
        'type' => 'team_member',
        'name' => 'Sarah Chen',
        'role' => 'Senior Backend Developer',
        'skills' => 'Python, PostgreSQL, Redis, Docker',
        'experience' => '5 years',
        'projects' => 'API Optimization, User Dashboard'
      }
    ]
    
    response = client.generate_response("What's the status of our performance issues?", project_data)
    puts "📊 Project Management Response:"
    puts response[:response]
  else  
    puts "❌ Project management provider not available"
  end
rescue Prescient::Error => e
  puts "❌ Error: #{e.message}"
end

# Example 4: Embedding Text Extraction
puts "\n--- Example 4: Embedding Text Extraction ---"

begin
  # Configure a provider with context configs
  Prescient.configure do |config|
    config.add_provider(:embedding_demo, Prescient::Provider::Ollama,
      url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
      embedding_model: 'nomic-embed-text',
      chat_model: 'llama3.1:8b',
      context_configs: {
        'blog_post' => {
          fields: %w[title content author tags category publish_date],
          format: '%{title} by %{author} in %{category}: %{content}',
          embedding_fields: %w[title content tags]  # Only these fields used for embeddings
        }
      }
    )
  end

  client = Prescient.client(:embedding_demo)
  
  if client.available?
    # Test embedding text extraction
    blog_post = {
      'type' => 'blog_post',
      'title' => 'Getting Started with AI',
      'content' => 'Artificial Intelligence is revolutionizing how we solve complex problems...',
      'author' => 'Dr. Smith',
      'tags' => 'AI machine-learning tutorial',
      'category' => 'Technology',
      'publish_date' => '2024-01-15'
    }

    # The extract_embedding_text method will only use title, content, and tags
    # This demonstrates how embedding generation can focus on specific fields
    embedding_text = client.provider.send(:extract_embedding_text, blog_post)
    puts "📊 Embedding Text Extracted:"
    puts "\"#{embedding_text}\""
    puts "\n(Notice how only title, content, and tags are included - not author, category, or date)"

    # Generate actual embedding
    puts "\n🔢 Generating embedding..."
    embedding = client.generate_embedding(embedding_text)
    puts "Generated embedding with #{embedding.length} dimensions"
  else
    puts "❌ Embedding demo provider not available"
  end
rescue Prescient::Error => e
  puts "❌ Error: #{e.message}"
end

# Example 5: No Context Configuration (Pure Default Behavior)
puts "\n--- Example 5: No Context Configuration ---"
puts "Shows how the system works without any context_configs defined."

Prescient.configure do |config|
  config.add_provider(:no_config, Prescient::Provider::Ollama,
    url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
    embedding_model: 'nomic-embed-text',
    chat_model: 'llama3.1:8b'
    # No context_configs defined - uses pure default behavior
  )
end

begin
  client = Prescient.client(:no_config)
  
  if client.available?
    # Random data structure - no predefined context type
    random_data = [
      {
        'title' => 'Meeting Notes',
        'content' => 'Discussed project timeline and deliverables',
        'author' => 'Jane Smith',
        'created_at' => '2024-01-20',
        'priority' => 'high'
      },
      {
        'name' => 'Server Performance',
        'description' => 'CPU usage spiked to 90% during peak hours',
        'severity' => 'warning',
        'timestamp' => '2024-01-20T10:30:00Z'
      }
    ]
    
    puts "🔧 Raw data (no context config):"
    random_data.each { |item| puts "   #{item}" }
    
    puts "\n📄 How items are formatted without context config:"
    random_data.each do |item|
      formatted = client.provider.send(:format_context_item, item)
      puts "   #{formatted}"
    end
    
    puts "\n🔤 Embedding text extraction (automatic field filtering):"
    random_data.each do |item|
      embedding_text = client.provider.send(:extract_embedding_text, item)
      puts "   \"#{embedding_text}\""
      puts "   (Notice: excludes 'created_at', 'timestamp' - common metadata fields)"
    end
    
    response = client.generate_response("Summarize the key issues", random_data)
    puts "\n🤖 AI Response (using default formatting):"
    puts response[:response]
  else
    puts "❌ No config provider not available"
  end
rescue Prescient::Error => e
  puts "❌ Error: #{e.message}"
end

puts "\n🎉 Custom context configurations completed!"
puts "\n💡 Key Features Demonstrated:"
puts "   ✅ User-defined context types (no hardcoded assumptions)"
puts "   ✅ Automatic context detection based on YOUR field configurations"
puts "   ✅ Custom field formatting with templates"
puts "   ✅ Selective embedding field extraction"
puts "   ✅ Fallback formatting for unconfigured data"
puts "   ✅ Works without any context configuration (pure default behavior)"
puts "\n🎯 Best Practices:"
puts "   - Define context_configs for your specific domain"
puts "   - Use explicit 'type' field when context detection isn't reliable"
puts "   - Exclude sensitive/metadata fields from embedding_fields"
puts "   - Test with and without context configs to see the difference"