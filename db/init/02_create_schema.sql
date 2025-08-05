-- Create database schema for storing embeddings and documents
-- This demonstrates a typical setup for vector similarity search

-- Documents table to store original content
CREATE TABLE IF NOT EXISTS documents (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    source_type VARCHAR(50), -- e.g., 'pdf', 'webpage', 'text', 'api'
    source_url VARCHAR(500),
    metadata JSONB, -- Additional flexible metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Document embeddings table for vector search
CREATE TABLE IF NOT EXISTS document_embeddings (
    id SERIAL PRIMARY KEY,
    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    embedding_provider VARCHAR(50) NOT NULL, -- e.g., 'ollama', 'openai', 'huggingface'
    embedding_model VARCHAR(100) NOT NULL, -- e.g., 'nomic-embed-text', 'text-embedding-3-small'
    embedding_dimensions INTEGER NOT NULL, -- e.g., 768, 1536, 384
    embedding VECTOR NOT NULL, -- The actual vector embedding
    embedding_text TEXT, -- The specific text that was embedded (may be subset of document)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Document chunks table for large documents split into smaller pieces
CREATE TABLE IF NOT EXISTS document_chunks (
    id SERIAL PRIMARY KEY,
    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL, -- Order of chunks within document
    chunk_text TEXT NOT NULL,
    chunk_metadata JSONB, -- Start/end positions, etc.
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(document_id, chunk_index)
);

-- Chunk embeddings table for chunked document search
CREATE TABLE IF NOT EXISTS chunk_embeddings (
    id SERIAL PRIMARY KEY,
    chunk_id INTEGER NOT NULL REFERENCES document_chunks(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    embedding_provider VARCHAR(50) NOT NULL,
    embedding_model VARCHAR(100) NOT NULL,
    embedding_dimensions INTEGER NOT NULL,
    embedding VECTOR NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Search queries table to store user queries and results
CREATE TABLE IF NOT EXISTS search_queries (
    id SERIAL PRIMARY KEY,
    query_text TEXT NOT NULL,
    embedding_provider VARCHAR(50) NOT NULL,
    embedding_model VARCHAR(100) NOT NULL,
    query_embedding VECTOR,
    result_count INTEGER,
    search_metadata JSONB, -- Search parameters, filters, etc.
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Query results table to store search results for analysis
CREATE TABLE IF NOT EXISTS query_results (
    id SERIAL PRIMARY KEY,
    query_id INTEGER NOT NULL REFERENCES search_queries(id) ON DELETE CASCADE,
    document_id INTEGER REFERENCES documents(id) ON DELETE CASCADE,
    chunk_id INTEGER REFERENCES document_chunks(id) ON DELETE CASCADE,
    similarity_score FLOAT NOT NULL,
    rank_position INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_documents_source_type ON documents(source_type);
CREATE INDEX IF NOT EXISTS idx_documents_created_at ON documents(created_at);
CREATE INDEX IF NOT EXISTS idx_documents_metadata ON documents USING GIN(metadata);

CREATE INDEX IF NOT EXISTS idx_document_embeddings_document_id ON document_embeddings(document_id);
CREATE INDEX IF NOT EXISTS idx_document_embeddings_provider_model ON document_embeddings(embedding_provider, embedding_model);
CREATE INDEX IF NOT EXISTS idx_document_embeddings_dimensions ON document_embeddings(embedding_dimensions);

CREATE INDEX IF NOT EXISTS idx_chunk_embeddings_chunk_id ON chunk_embeddings(chunk_id);
CREATE INDEX IF NOT EXISTS idx_chunk_embeddings_document_id ON chunk_embeddings(document_id);
CREATE INDEX IF NOT EXISTS idx_chunk_embeddings_provider_model ON chunk_embeddings(embedding_provider, embedding_model);

CREATE INDEX IF NOT EXISTS idx_search_queries_created_at ON search_queries(created_at);
CREATE INDEX IF NOT EXISTS idx_query_results_query_id ON query_results(query_id);
CREATE INDEX IF NOT EXISTS idx_query_results_similarity_score ON query_results(similarity_score);

-- Add comments for documentation
COMMENT ON TABLE documents IS 'Stores original documents and content';
COMMENT ON TABLE document_embeddings IS 'Stores vector embeddings for entire documents';
COMMENT ON TABLE document_chunks IS 'Stores chunks of large documents for better search granularity';
COMMENT ON TABLE chunk_embeddings IS 'Stores vector embeddings for document chunks';
COMMENT ON TABLE search_queries IS 'Stores user search queries and their embeddings';
COMMENT ON TABLE query_results IS 'Stores search results for analysis and optimization';

COMMENT ON COLUMN document_embeddings.embedding IS 'Vector embedding generated by AI provider';
COMMENT ON COLUMN chunk_embeddings.embedding IS 'Vector embedding for document chunk';
COMMENT ON COLUMN search_queries.query_embedding IS 'Vector embedding of the search query';

-- Log successful schema creation
DO $$
BEGIN
    RAISE NOTICE 'Database schema created successfully';
END $$;