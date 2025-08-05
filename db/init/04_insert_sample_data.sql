-- Insert sample data for testing and demonstration
-- This provides realistic examples of how to structure data for vector search

-- Insert sample documents
INSERT INTO documents (title, content, source_type, source_url, metadata) VALUES
    ('Ruby Programming Basics', 
     'Ruby is a dynamic, open-source programming language with a focus on simplicity and productivity. It has an elegant syntax that is natural to read and easy to write. Ruby supports multiple programming paradigms, including procedural, object-oriented, and functional programming.',
     'article', 
     'https://example.com/ruby-basics',
     '{"tags": ["programming", "ruby", "beginner"], "author": "Jane Doe", "difficulty": "beginner"}'::jsonb),
     
    ('Machine Learning with Python',
     'Machine learning is a subset of artificial intelligence that enables computers to learn and make decisions from data without being explicitly programmed. Python has become the go-to language for machine learning due to its rich ecosystem of libraries like scikit-learn, TensorFlow, and PyTorch.',
     'article',
     'https://example.com/ml-python',
     '{"tags": ["machine-learning", "python", "ai"], "author": "John Smith", "difficulty": "intermediate"}'::jsonb),
     
    ('Vector Databases Explained',
     'Vector databases are specialized databases designed to store and query high-dimensional vectors. They are essential for similarity search, recommendation systems, and AI applications. Popular vector databases include Pinecone, Weaviate, and PostgreSQL with pgvector extension.',
     'tutorial',
     'https://example.com/vector-databases',
     '{"tags": ["databases", "vectors", "similarity-search"], "author": "Alice Johnson", "difficulty": "advanced"}'::jsonb),
     
    ('API Design Best Practices',
     'RESTful API design follows specific principles to create maintainable and scalable web services. Key principles include using HTTP methods correctly, designing intuitive URLs, handling errors gracefully, and providing clear documentation. Rate limiting and authentication are also crucial considerations.',
     'guide',
     'https://example.com/api-design',
     '{"tags": ["api", "rest", "web-development"], "author": "Bob Wilson", "difficulty": "intermediate"}'::jsonb),
     
    ('Docker Container Security',
     'Container security involves multiple layers of protection, from the host system to the container runtime and the applications themselves. Key practices include using minimal base images, scanning for vulnerabilities, implementing proper access controls, and monitoring container behavior in production.',
     'security-guide',
     'https://example.com/docker-security',
     '{"tags": ["docker", "security", "containers"], "author": "Carol Brown", "difficulty": "advanced"}'::jsonb);

-- Insert sample chunks for the longer documents
-- Breaking documents into smaller chunks for better search granularity
INSERT INTO document_chunks (document_id, chunk_index, chunk_text, chunk_metadata) VALUES
    (1, 1, 'Ruby is a dynamic, open-source programming language with a focus on simplicity and productivity.', 
     '{"start_pos": 0, "end_pos": 93, "word_count": 15}'::jsonb),
    (1, 2, 'It has an elegant syntax that is natural to read and easy to write.',
     '{"start_pos": 94, "end_pos": 161, "word_count": 13}'::jsonb),
    (1, 3, 'Ruby supports multiple programming paradigms, including procedural, object-oriented, and functional programming.',
     '{"start_pos": 162, "end_pos": 274, "word_count": 14}'::jsonb),
     
    (2, 1, 'Machine learning is a subset of artificial intelligence that enables computers to learn and make decisions from data without being explicitly programmed.',
     '{"start_pos": 0, "end_pos": 147, "word_count": 23}'::jsonb),
    (2, 2, 'Python has become the go-to language for machine learning due to its rich ecosystem of libraries like scikit-learn, TensorFlow, and PyTorch.',
     '{"start_pos": 148, "end_pos": 285, "word_count": 22}'::jsonb),
     
    (3, 1, 'Vector databases are specialized databases designed to store and query high-dimensional vectors.',
     '{"start_pos": 0, "end_pos": 95, "word_count": 14}'::jsonb),
    (3, 2, 'They are essential for similarity search, recommendation systems, and AI applications.',
     '{"start_pos": 96, "end_pos": 179, "word_count": 12}'::jsonb),
    (3, 3, 'Popular vector databases include Pinecone, Weaviate, and PostgreSQL with pgvector extension.',
     '{"start_pos": 180, "end_pos": 272, "word_count": 13}'::jsonb);

-- Note: In a real application, you would generate embeddings using the Prescient gem
-- and insert them into document_embeddings and chunk_embeddings tables.
-- 
-- Example workflow:
-- 1. Insert document into documents table
-- 2. Generate embedding using Prescient gem: 
--    embedding = Prescient.generate_embedding(document.content)
-- 3. Insert embedding into document_embeddings table
-- 4. For large documents, split into chunks and generate embeddings for each chunk

-- Insert sample search queries for demonstration
INSERT INTO search_queries (query_text, embedding_provider, embedding_model, result_count, search_metadata) VALUES
    ('How to learn Ruby programming?', 'ollama', 'nomic-embed-text', 3, 
     '{"search_type": "semantic", "filters": {"difficulty": "beginner"}}'::jsonb),
    ('Vector similarity search techniques', 'openai', 'text-embedding-3-small', 2,
     '{"search_type": "semantic", "filters": {"tags": ["vectors", "databases"]}}'::jsonb),
    ('Python machine learning libraries', 'ollama', 'nomic-embed-text', 5,
     '{"search_type": "semantic", "filters": {"tags": ["python", "machine-learning"]}}'::jsonb);

-- Create a view for easy querying of documents with their embeddings
CREATE OR REPLACE VIEW documents_with_embeddings AS
SELECT 
    d.id,
    d.title,
    d.content,
    d.source_type,
    d.source_url,
    d.metadata,
    d.created_at,
    de.embedding_provider,
    de.embedding_model,
    de.embedding_dimensions,
    de.embedding,
    de.embedding_text
FROM documents d
LEFT JOIN document_embeddings de ON d.id = de.document_id;

-- Create a view for easy querying of chunks with their embeddings
CREATE OR REPLACE VIEW chunks_with_embeddings AS
SELECT 
    dc.id as chunk_id,
    dc.document_id,
    dc.chunk_index,
    dc.chunk_text,
    dc.chunk_metadata,
    d.title as document_title,
    d.source_type,
    ce.embedding_provider,
    ce.embedding_model,
    ce.embedding_dimensions,
    ce.embedding
FROM document_chunks dc
JOIN documents d ON dc.document_id = d.id
LEFT JOIN chunk_embeddings ce ON dc.id = ce.chunk_id
ORDER BY dc.document_id, dc.chunk_index;

-- Log successful sample data insertion
DO $$
BEGIN
    RAISE NOTICE 'Sample data inserted successfully';
    RAISE NOTICE 'Documents: %', (SELECT COUNT(*) FROM documents);
    RAISE NOTICE 'Chunks: %', (SELECT COUNT(*) FROM document_chunks);
    RAISE NOTICE 'Sample queries: %', (SELECT COUNT(*) FROM search_queries);
END $$;