#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Vector similarity search with Prescient gem and PostgreSQL pgvector
# This example demonstrates how to store embeddings and perform similarity search

require_relative '../lib/prescient'
require 'pg'
require 'json'

puts "=== Vector Similarity Search Example ==="
puts "This example shows how to use Prescient with PostgreSQL pgvector for semantic search."

# Database connection configuration
DB_CONFIG = {
  host: ENV.fetch('DB_HOST', 'localhost'),
  port: ENV.fetch('DB_PORT', '5432'),
  dbname: ENV.fetch('DB_NAME', 'prescient_development'),
  user: ENV.fetch('DB_USER', 'prescient'),
  password: ENV.fetch('DB_PASSWORD', 'prescient_password')
}.freeze

class VectorSearchExample
  def initialize
    @db = PG.connect(DB_CONFIG)
    @client = Prescient.client(:ollama)
  end

  def run_example
    puts "\n--- Setting up vector search example ---"
    
    # Check if services are available
    unless check_services_available
      puts "❌ Required services not available. Please start with: docker-compose up -d"
      return
    end

    # 1. Generate and store embeddings for existing documents
    puts "\n📊 Generating embeddings for sample documents..."
    generate_document_embeddings

    # 2. Perform similarity search
    puts "\n🔍 Performing similarity searches..."
    search_examples

    # 3. Advanced search with filtering
    puts "\n🎯 Advanced search with metadata filtering..."
    advanced_search_examples

    # 4. Demonstrate different distance functions
    puts "\n📏 Comparing different distance functions..."
    compare_distance_functions

    puts "\n🎉 Vector search example completed!"
  end

  private

  def check_services_available
    # Check database connection
    begin
      result = @db.exec("SELECT 1")
      puts "✅ PostgreSQL connected"
    rescue PG::Error => e
      puts "❌ PostgreSQL connection failed: #{e.message}"
      return false
    end

    # Check pgvector extension
    begin
      result = @db.exec("SELECT * FROM pg_extension WHERE extname = 'vector'")
      if result.ntuples > 0
        puts "✅ pgvector extension available"
      else
        puts "❌ pgvector extension not found"
        return false
      end
    rescue PG::Error => e
      puts "❌ pgvector check failed: #{e.message}"
      return false
    end

    # Check Ollama connection
    if @client.available?
      puts "✅ Ollama connected"
    else
      puts "❌ Ollama not available"
      return false
    end

    true
  end

  def generate_document_embeddings
    # Get documents that don't have embeddings yet
    query = <<~SQL
      SELECT d.id, d.title, d.content 
      FROM documents d
      LEFT JOIN document_embeddings de ON d.id = de.document_id 
        AND de.embedding_provider = 'ollama' 
        AND de.embedding_model = 'nomic-embed-text'
      WHERE de.id IS NULL
      LIMIT 10
    SQL

    result = @db.exec(query)
    
    if result.ntuples == 0
      puts "   All documents already have embeddings"
      return
    end

    result.each do |row|
      document_id = row['id']
      title = row['title']
      content = row['content']
      
      puts "   Generating embedding for: #{title}"
      
      begin
        # Generate embedding using Prescient
        embedding = @client.generate_embedding(content)
        
        # Store in database
        insert_embedding(document_id, embedding, content, 'ollama', 'nomic-embed-text', 768)
        
        puts "   ✅ Stored embedding (#{embedding.length} dimensions)"
        
      rescue Prescient::Error => e
        puts "   ❌ Failed to generate embedding: #{e.message}"
      end
    end
  end

  def insert_embedding(document_id, embedding, text, provider, model, dimensions)
    # Convert Ruby array to PostgreSQL vector format
    vector_str = "[#{embedding.join(',')}]"
    
    query = <<~SQL
      INSERT INTO document_embeddings 
      (document_id, embedding_provider, embedding_model, embedding_dimensions, embedding, embedding_text)
      VALUES ($1, $2, $3, $4, $5, $6)
    SQL
    
    @db.exec_params(query, [document_id, provider, model, dimensions, vector_str, text])
  end

  def search_examples
    search_queries = [
      "How to learn programming?",
      "What is machine learning?",
      "Database optimization techniques",
      "API security best practices"
    ]

    search_queries.each do |query_text|
      puts "\n🔍 Searching for: '#{query_text}'"
      perform_similarity_search(query_text, limit: 3)
    end
  end

  def perform_similarity_search(query_text, limit: 5, distance_function: 'cosine')
    begin
      # Generate embedding for query
      query_embedding = @client.generate_embedding(query_text)
      query_vector = "[#{query_embedding.join(',')}]"
      
      # Choose distance operator based on function
      distance_op = case distance_function
                   when 'cosine' then '<=>'
                   when 'l2' then '<->'
                   when 'inner_product' then '<#>'
                   else '<=>'
                   end

      # Perform similarity search
      search_query = <<~SQL
        SELECT 
          d.title,
          d.content,
          d.metadata,
          de.embedding #{distance_op} $1::vector AS distance,
          1 - (de.embedding <=> $1::vector) AS cosine_similarity
        FROM documents d
        JOIN document_embeddings de ON d.id = de.document_id
        WHERE de.embedding_provider = 'ollama' 
          AND de.embedding_model = 'nomic-embed-text'
        ORDER BY de.embedding #{distance_op} $1::vector
        LIMIT $2
      SQL

      result = @db.exec_params(search_query, [query_vector, limit])
      
      if result.ntuples == 0
        puts "   No results found"
        return
      end

      result.each_with_index do |row, index|
        similarity = (row['cosine_similarity'].to_f * 100).round(1)
        puts "   #{index + 1}. #{row['title']} (#{similarity}% similar)"
        puts "      #{row['content'][0..100]}..."
        
        # Show metadata if available
        if row['metadata'] && !row['metadata'].empty?
          metadata = JSON.parse(row['metadata'])
          tags = metadata['tags']&.join(', ')
          puts "      Tags: #{tags}" if tags
        end
        puts
      end
      
    rescue Prescient::Error => e
      puts "   ❌ Search failed: #{e.message}"
    rescue PG::Error => e
      puts "   ❌ Database error: #{e.message}"
    end
  end

  def advanced_search_examples
    # Search with metadata filtering
    puts "\n🎯 Search for programming content with beginner difficulty:"
    advanced_search("programming basics", tags: ["programming"], difficulty: "beginner")
    
    puts "\n🎯 Search for AI/ML content:"
    advanced_search("artificial intelligence", tags: ["ai", "machine-learning"])
  end

  def advanced_search(query_text, filters = {})
    begin
      query_embedding = @client.generate_embedding(query_text)
      query_vector = "[#{query_embedding.join(',')}]"
      
      # Build WHERE clause for metadata filtering
      where_conditions = ["de.embedding_provider = 'ollama'", "de.embedding_model = 'nomic-embed-text'"]
      params = [query_vector]
      param_index = 2

      filters.each do |key, value|
        case key
        when :tags
          # Filter by tags array overlap
          where_conditions << "d.metadata->'tags' ?| $#{param_index}::text[]"
          params << value
          param_index += 1
        when :difficulty
          # Filter by exact difficulty match
          where_conditions << "d.metadata->>'difficulty' = $#{param_index}"
          params << value
          param_index += 1
        when :source_type
          # Filter by source type
          where_conditions << "d.source_type = $#{param_index}"
          params << value
          param_index += 1
        end
      end

      search_query = <<~SQL
        SELECT 
          d.title,
          d.content,
          d.metadata,
          de.embedding <=> $1::vector AS cosine_distance,
          1 - (de.embedding <=> $1::vector) AS cosine_similarity
        FROM documents d
        JOIN document_embeddings de ON d.id = de.document_id
        WHERE #{where_conditions.join(' AND ')}
        ORDER BY de.embedding <=> $1::vector
        LIMIT 3
      SQL

      result = @db.exec_params(search_query, params)
      
      if result.ntuples == 0
        puts "   No results found with the specified filters"
        return
      end

      result.each_with_index do |row, index|
        similarity = (row['cosine_similarity'].to_f * 100).round(1)
        puts "   #{index + 1}. #{row['title']} (#{similarity}% similar)"
        
        metadata = JSON.parse(row['metadata'])
        puts "      Difficulty: #{metadata['difficulty']}"
        puts "      Tags: #{metadata['tags']&.join(', ')}"
        puts "      #{row['content'][0..80]}..."
        puts
      end
      
    rescue Prescient::Error => e
      puts "   ❌ Search failed: #{e.message}"
    rescue PG::Error => e
      puts "   ❌ Database error: #{e.message}"
    end
  end

  def compare_distance_functions
    query_text = "programming languages and development"
    
    puts "\n📏 Comparing distance functions for: '#{query_text}'"
    
    %w[cosine l2 inner_product].each do |distance_func|
      puts "\n   #{distance_func.upcase} Distance:"
      perform_similarity_search(query_text, limit: 2, distance_function: distance_func)
    end
  end

  def cleanup
    @db.close if @db
  end
end

# Run the example
begin
  example = VectorSearchExample.new
  example.run_example
rescue StandardError => e
  puts "❌ Example failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
ensure
  example&.cleanup
end

puts "\n💡 Next steps:"
puts "   - Try different embedding models (OpenAI, HuggingFace)"
puts "   - Implement hybrid search (vector + keyword)"
puts "   - Add document chunking for large texts"
puts "   - Experiment with different similarity thresholds"
puts "   - Add result re-ranking and filtering"