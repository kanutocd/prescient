# frozen_string_literal: true

# Rails migration for Prescient gem vector database tables
# Copy this file to your Rails db/migrate directory and adjust the timestamp

class CreatePrescientTables < ActiveRecord::Migration[7.0]
  def up
    # Enable pgvector extension
    enable_extension 'vector'

    # Documents table to store original content
    create_table :documents do |t|
      t.string :title, null: false, limit: 255
      t.text :content, null: false
      t.string :source_type, limit: 50 # e.g., 'pdf', 'webpage', 'text', 'api'
      t.string :source_url, limit: 500
      t.jsonb :metadata # Additional flexible metadata
      t.timestamps
    end

    # Document embeddings table for vector search
    create_table :document_embeddings do |t|
      t.references :document, null: false, foreign_key: { on_delete: :cascade }
      t.string :embedding_provider, null: false, limit: 50 # e.g., 'ollama', 'openai'
      t.string :embedding_model, null: false, limit: 100 # e.g., 'nomic-embed-text'
      t.integer :embedding_dimensions, null: false # e.g., 768, 1536, 384
      t.vector :embedding, null: false # The actual vector embedding
      t.text :embedding_text # The specific text that was embedded
      t.timestamps
    end

    # Document chunks table for large documents split into smaller pieces
    create_table :document_chunks do |t|
      t.references :document, null: false, foreign_key: { on_delete: :cascade }
      t.integer :chunk_index, null: false # Order of chunks within document
      t.text :chunk_text, null: false
      t.jsonb :chunk_metadata # Start/end positions, etc.
      t.timestamps
    end

    # Chunk embeddings table for chunked document search
    create_table :chunk_embeddings do |t|
      t.references :chunk, null: false, foreign_key: { to_table: :document_chunks, on_delete: :cascade }
      t.references :document, null: false, foreign_key: { on_delete: :cascade }
      t.string :embedding_provider, null: false, limit: 50
      t.string :embedding_model, null: false, limit: 100
      t.integer :embedding_dimensions, null: false
      t.vector :embedding, null: false
      t.timestamps
    end

    # Search queries table to store user queries and results
    create_table :search_queries do |t|
      t.text :query_text, null: false
      t.string :embedding_provider, null: false, limit: 50
      t.string :embedding_model, null: false, limit: 100
      t.vector :query_embedding
      t.integer :result_count
      t.jsonb :search_metadata # Search parameters, filters, etc.
      t.timestamps
    end

    # Query results table to store search results for analysis
    create_table :query_results do |t|
      t.references :query, null: false, foreign_key: { to_table: :search_queries, on_delete: :cascade }
      t.references :document, null: true, foreign_key: { on_delete: :cascade }
      t.references :chunk, null: true, foreign_key: { to_table: :document_chunks, on_delete: :cascade }
      t.float :similarity_score, null: false
      t.integer :rank_position, null: false
      t.timestamps
    end

    # Add indexes for better performance
    add_index :documents, :source_type
    add_index :documents, :created_at
    add_index :documents, :metadata, using: :gin

    add_index :document_embeddings, :document_id
    add_index :document_embeddings, [:embedding_provider, :embedding_model], name: 'idx_doc_embeddings_provider_model'
    add_index :document_embeddings, :embedding_dimensions

    add_index :document_chunks, [:document_id, :chunk_index], unique: true

    add_index :chunk_embeddings, :chunk_id
    add_index :chunk_embeddings, :document_id
    add_index :chunk_embeddings, [:embedding_provider, :embedding_model], name: 'idx_chunk_embeddings_provider_model'

    add_index :search_queries, :created_at
    add_index :query_results, :query_id
    add_index :query_results, :similarity_score

    # Create vector similarity indexes for fast search
    # Using HNSW (Hierarchical Navigable Small World) for approximate nearest neighbor search

    # Vector indexes for document embeddings
    execute <<-SQL
      CREATE INDEX idx_document_embeddings_cosine 
      ON document_embeddings 
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64);
    SQL

    execute <<-SQL
      CREATE INDEX idx_document_embeddings_l2 
      ON document_embeddings 
      USING hnsw (embedding vector_l2_ops)
      WITH (m = 16, ef_construction = 64);
    SQL

    # Vector indexes for chunk embeddings
    execute <<-SQL
      CREATE INDEX idx_chunk_embeddings_cosine 
      ON chunk_embeddings 
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64);
    SQL

    execute <<-SQL
      CREATE INDEX idx_chunk_embeddings_l2 
      ON chunk_embeddings 
      USING hnsw (embedding vector_l2_ops)
      WITH (m = 16, ef_construction = 64);
    SQL

    # Add helpful functions
    execute <<-SQL
      CREATE OR REPLACE FUNCTION cosine_similarity(a vector, b vector)
      RETURNS float AS $$
      BEGIN
          RETURN 1 - (a <=> b);
      END;
      $$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;
    SQL

    execute <<-SQL
      CREATE OR REPLACE FUNCTION euclidean_distance(a vector, b vector)
      RETURNS float AS $$
      BEGIN
          RETURN a <-> b;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;
    SQL
  end

  def down
    drop_table :query_results
    drop_table :search_queries
    drop_table :chunk_embeddings
    drop_table :document_chunks
    drop_table :document_embeddings
    drop_table :documents

    execute 'DROP FUNCTION IF EXISTS cosine_similarity(vector, vector);'
    execute 'DROP FUNCTION IF EXISTS euclidean_distance(vector, vector);'

    disable_extension 'vector'
  end
end