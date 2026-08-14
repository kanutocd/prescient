#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Vector similarity search with Prescient and PostgreSQL pgvector.
# The Store owns only its embedding table; applications own their documents.

require_relative '../lib/prescient'
require 'pg'

puts '=== Vector Similarity Search Example ==='

DB_CONFIG = {
  host:     ENV.fetch('DB_HOST', 'localhost'),
  port:     ENV.fetch('DB_PORT', '5432'),
  dbname:   ENV.fetch('DB_NAME', 'prescient_development'),
  user:     ENV.fetch('DB_USER', 'prescient'),
  password: ENV.fetch('DB_PASSWORD', 'prescient_password'),
}.freeze

class VectorSearchExample
  EMBEDDING_DIMENSIONS = 768
  EMBEDDING_MODEL = 'nomic-embed-text'

  def initialize
    @connection = PG.connect(DB_CONFIG)
    @client = Prescient.client(:ollama, enable_fallback: false)
    @store = Prescient::Pgvector::Store.new(
      connection: @connection,
      dimensions: EMBEDDING_DIMENSIONS,
    )
  end

  def run
    @store.install!
    %i[cosine euclidean inner_product].each { |metric| @store.create_index!(metric:) }

    documents.each do |document|
      embedding = @client.generate_embedding(document[:content], model: EMBEDDING_MODEL)
      @store.upsert(
        id: document[:id],
        embedding:,
        provider: 'ollama',
        model: EMBEDDING_MODEL,
        content: document[:content],
        metadata: { title: document[:title] },
      )
    end

    query = 'How do I improve database performance?'
    embedding = @client.generate_embedding(query, model: EMBEDDING_MODEL)
    results = @store.search(
      embedding:,
      limit: 3,
      metric: :cosine,
      provider: 'ollama',
      model: EMBEDDING_MODEL,
    )

    puts "\nQuery: #{query}"
    results.each_with_index do |result, index|
      title = result[:metadata].fetch('title')
      puts "#{index + 1}. #{title} (distance: #{result[:distance].round(4)})"
      puts "   #{result[:content]}"
    end
  rescue Prescient::Error, PG::Error => e
    warn "Vector search failed: #{e.message}"
  ensure
    @connection&.close
  end

  private

  def documents
    [
      {
        id:      'postgres-indexes',
        title:   'PostgreSQL indexes',
        content: 'Indexes can reduce query latency when their columns match common filters and ordering.',
      },
      {
        id:      'ruby-performance',
        title:   'Ruby performance',
        content: 'Measure allocations and repeated work before optimizing a Ruby application.',
      },
      {
        id:      'api-security',
        title:   'API security',
        content: 'Protect API credentials, validate inputs, and avoid exposing provider response bodies.',
      },
    ]
  end
end

VectorSearchExample.new.run
