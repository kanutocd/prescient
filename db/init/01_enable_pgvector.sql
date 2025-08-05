-- Enable pgvector extension for vector operations
-- This script runs automatically when the PostgreSQL container starts

-- Enable the pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Verify the extension is loaded
SELECT * FROM pg_extension WHERE extname = 'vector';

-- Create a custom vector function for cosine similarity (if needed)
CREATE OR REPLACE FUNCTION cosine_similarity(a vector, b vector)
RETURNS float AS $$
BEGIN
    RETURN 1 - (a <=> b);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;

-- Create a custom function for euclidean distance (if needed)
CREATE OR REPLACE FUNCTION euclidean_distance(a vector, b vector)
RETURNS float AS $$
BEGIN
    RETURN a <-> b;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;

-- Log successful initialization
DO $$
BEGIN
    RAISE NOTICE 'pgvector extension enabled successfully';
END $$;