-- Create vector similarity indexes for optimal search performance
-- These indexes are crucial for fast similarity search with large datasets

-- Vector indexes for document embeddings
-- Using HNSW (Hierarchical Navigable Small World) for approximate nearest neighbor search
-- Different distance functions: L2 distance (<->), inner product (<#>), cosine distance (<=>)

-- Index for L2 distance (Euclidean) - good general purpose
CREATE INDEX IF NOT EXISTS idx_document_embeddings_l2 
ON document_embeddings 
USING hnsw (embedding vector_l2_ops)
WITH (m = 16, ef_construction = 64);

-- Index for cosine distance - good for normalized embeddings
CREATE INDEX IF NOT EXISTS idx_document_embeddings_cosine 
ON document_embeddings 
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Index for inner product - good for some specific use cases
CREATE INDEX IF NOT EXISTS idx_document_embeddings_ip 
ON document_embeddings 
USING hnsw (embedding vector_ip_ops)
WITH (m = 16, ef_construction = 64);

-- Vector indexes for chunk embeddings (same pattern)
CREATE INDEX IF NOT EXISTS idx_chunk_embeddings_l2 
ON chunk_embeddings 
USING hnsw (embedding vector_l2_ops)
WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_chunk_embeddings_cosine 
ON chunk_embeddings 
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_chunk_embeddings_ip 
ON chunk_embeddings 
USING hnsw (embedding vector_ip_ops)
WITH (m = 16, ef_construction = 64);

-- Vector indexes for search queries
CREATE INDEX IF NOT EXISTS idx_search_queries_l2 
ON search_queries 
USING hnsw (query_embedding vector_l2_ops)
WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_search_queries_cosine 
ON search_queries 
USING hnsw (query_embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Composite indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_document_embeddings_provider_dimensions_l2
ON document_embeddings 
USING hnsw (embedding vector_l2_ops)
INCLUDE (embedding_provider, embedding_model, embedding_dimensions)
WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_chunk_embeddings_document_cosine
ON chunk_embeddings 
USING hnsw (embedding vector_cosine_ops)
INCLUDE (document_id, embedding_provider, embedding_model)
WITH (m = 16, ef_construction = 64);

-- Partial indexes for specific providers (more efficient if you mainly use one provider)
-- Uncomment and modify these based on your primary use case:

-- CREATE INDEX IF NOT EXISTS idx_document_embeddings_ollama_cosine
-- ON document_embeddings 
-- USING hnsw (embedding vector_cosine_ops)
-- WITH (m = 16, ef_construction = 64)
-- WHERE embedding_provider = 'ollama';

-- CREATE INDEX IF NOT EXISTS idx_chunk_embeddings_openai_cosine
-- ON chunk_embeddings 
-- USING hnsw (embedding vector_cosine_ops)
-- WITH (m = 16, ef_construction = 64)
-- WHERE embedding_provider = 'openai';

-- HNSW Index parameters explanation:
-- m: maximum number of connections for each node (16 is good default)
-- ef_construction: size of dynamic candidate list (64 is good default)
-- Higher values = better accuracy but slower build time and more memory

-- For very large datasets (millions of vectors), consider:
-- m = 32, ef_construction = 128 for better accuracy
-- m = 8, ef_construction = 32 for faster build/less memory

-- Log successful index creation
DO $$
BEGIN
    RAISE NOTICE 'Vector similarity indexes created successfully';
    RAISE NOTICE 'Index parameters: m=16, ef_construction=64';
    RAISE NOTICE 'Distance functions: L2, Cosine, Inner Product';
END $$;