# Vector Search with Prescient and pgvector

This guide provides a comprehensive overview of using Prescient with PostgreSQL's pgvector extension for semantic search and similarity matching.

## Quick Start

### 1. Start Services

```bash
# Start PostgreSQL with pgvector and Ollama
docker-compose up -d postgres ollama

# Wait for services to be ready
docker-compose logs -f postgres ollama
```

### 2. Initialize Models

```bash
# Pull required Ollama models
docker-compose up ollama-init

# Or manually:
./scripts/setup-ollama-models.sh
```

### 3. Run Vector Search Example

```bash
# Set environment variables
export DB_HOST=localhost
export OLLAMA_URL=http://localhost:11434

# Run the example
ruby examples/vector_search.rb
```

## Architecture Overview

### Database Schema

```
documents
├── id (Primary Key)
├── title
├── content
├── source_type
├── source_url
├── metadata (JSONB)
└── timestamps

document_embeddings
├── id (Primary Key)
├── document_id (Foreign Key)
├── embedding_provider
├── embedding_model
├── embedding_dimensions
├── embedding (VECTOR)
├── embedding_text
└── timestamps

document_chunks
├── id (Primary Key)
├── document_id (Foreign Key)
├── chunk_index
├── chunk_text
├── chunk_metadata (JSONB)
└── timestamps

chunk_embeddings
├── id (Primary Key)
├── chunk_id (Foreign Key)
├── document_id (Foreign Key)
├── embedding_provider
├── embedding_model
├── embedding_dimensions
├── embedding (VECTOR)
└── timestamps
```

### Vector Indexes

The setup automatically creates HNSW indexes for optimal performance:

- **Cosine Distance**: `embedding <=> query_vector`
- **L2 Distance**: `embedding <-> query_vector`
- **Inner Product**: `embedding <#> query_vector`

## Common Workflows

### 1. Document Ingestion

```ruby
require 'prescient'
require 'pg'

# Connect to database
db = PG.connect(
  host: 'localhost',
  dbname: 'prescient_development',
  user: 'prescient',
  password: 'prescient_password'
)

client = Prescient.client(:ollama)

# Insert document
doc_result = db.exec_params(
  "INSERT INTO documents (title, content, source_type, metadata) VALUES ($1, $2, $3, $4) RETURNING id",
  [title, content, 'article', metadata.to_json]
)
document_id = doc_result[0]['id']

# Generate and store embedding
embedding = client.generate_embedding(content)
vector_str = "[#{embedding.join(',')}]"

db.exec_params(
  "INSERT INTO document_embeddings (document_id, embedding_provider, embedding_model, embedding_dimensions, embedding, embedding_text) VALUES ($1, $2, $3, $4, $5, $6)",
  [document_id, 'ollama', 'nomic-embed-text', 768, vector_str, content]
)
```

### 2. Similarity Search

```ruby
# Basic similarity search
query_text = "machine learning algorithms"
query_embedding = client.generate_embedding(query_text)
query_vector = "[#{query_embedding.join(',')}]"

results = db.exec_params(
  "SELECT d.title, d.content, de.embedding <=> $1::vector AS distance
   FROM documents d
   JOIN document_embeddings de ON d.id = de.document_id
   ORDER BY de.embedding <=> $1::vector
   LIMIT 5",
  [query_vector]
)

results.each do |row|
  similarity = 1 - row['distance'].to_f
  puts "#{ row['title']} (#{ (similarity * 100).round(1)}% similar)"
end
```

### 3. Filtered Search

```ruby
# Search with metadata filtering
results = db.exec_params(
  "SELECT d.title, de.embedding <=> $1::vector as distance
   FROM documents d
   JOIN document_embeddings de ON d.id = de.document_id
   WHERE d.metadata->'tags' ? 'programming'
     AND d.metadata->>'difficulty' = 'beginner'
   ORDER BY de.embedding <=> $1::vector
   LIMIT 10",
  [query_vector]
)
```

### 4. Document Chunking

For large documents, split into chunks for better search granularity:

```ruby
def chunk_document(text, chunk_size: 500, overlap: 50)
  chunks = []
  start = 0

  while start < text.length
    end_pos = [start + chunk_size, text.length].min

    # Find word boundary to avoid cutting words
    if end_pos < text.length
      while end_pos > start && text[end_pos] != ' '
        end_pos -= 1
      end
    end

    chunk = text[start...end_pos].strip
    chunks << {
      text: chunk,
      start_pos: start,
      end_pos: end_pos,
      index: chunks.length
    }

    start = end_pos - overlap
    break if start >= text.length
  end

  chunks
end

# Process chunks
chunks = chunk_document(document.content)
chunks.each do |chunk|
  # Insert chunk
  chunk_result = db.exec_params(
    "INSERT INTO document_chunks (document_id, chunk_index, chunk_text, chunk_metadata) VALUES ($1, $2, $3, $4) RETURNING id",
    [document_id, chunk[:index], chunk[:text], { start_pos: chunk[:start_pos], end_pos: chunk[:end_pos]}.to_json]
  )
  chunk_id = chunk_result[0]['id']

  # Generate embedding for chunk
  chunk_embedding = client.generate_embedding(chunk[:text])
  chunk_vector = "[#{chunk_embedding.join(',')}]"

  # Store chunk embedding
  db.exec_params(
    "INSERT INTO chunk_embeddings (chunk_id, document_id, embedding_provider, embedding_model, embedding_dimensions, embedding) VALUES ($1, $2, $3, $4, $5, $6)",
    [chunk_id, document_id, 'ollama', 'nomic-embed-text', 768, chunk_vector]
  )
end
```

## Performance Optimization

### Index Tuning

For different dataset sizes and performance requirements:

```sql
-- Small datasets (< 100K vectors): Fast build, good accuracy
CREATE INDEX idx_embeddings_small
ON document_embeddings
USING hnsw (embedding vector_cosine_ops)
WITH (m = 8, ef_construction = 32);

-- Medium datasets (100K - 1M vectors): Balanced
CREATE INDEX idx_embeddings_medium
ON document_embeddings
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Large datasets (> 1M vectors): High accuracy
CREATE INDEX idx_embeddings_large
ON document_embeddings
USING hnsw (embedding vector_cosine_ops)
WITH (m = 32, ef_construction = 128);
```

### Query Optimization

```sql
-- Adjust search quality vs speed
SET hnsw.ef_search = 40;   -- Fast search, lower accuracy
SET hnsw.ef_search = 100;  -- Balanced (default)
SET hnsw.ef_search = 200;  -- High accuracy, slower

-- Monitor query performance
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM document_embeddings
ORDER BY embedding <=> '[0.1,0.2,...]'::vector
LIMIT 10;
```

### Batch Operations

```ruby
# Batch embed multiple texts for efficiency
texts = documents.map(&:content)
embeddings = []

texts.each_slice(10) do |batch|
  batch.each do |text|
    embedding = client.generate_embedding(text)
    embeddings << embedding

    # Small delay to avoid rate limiting
    sleep(0.1)
  end
end

# Batch insert embeddings
db.transaction do
  embeddings.each_with_index do |embedding, index|
    vector_str = "[#{embedding.join(',')}]"
    db.exec_params(
      "INSERT INTO document_embeddings (...) VALUES (...)",
      [documents[index].id, 'ollama', 'nomic-embed-text', 768, vector_str, texts[index]]
    )
  end
end
```

## Advanced Features

### Hybrid Search

Combine vector similarity with traditional text search:

```sql
WITH vector_results AS (
  SELECT document_id, embedding <=> $1::vector as distance
  FROM document_embeddings
  ORDER BY embedding <=> $1::vector
  LIMIT 20
),
text_results AS (
  SELECT id as document_id, ts_rank(to_tsvector(content), plainto_tsquery($2)) as rank
  FROM documents
  WHERE to_tsvector(content) @@ plainto_tsquery($2)
)
SELECT d.title, d.content,
       COALESCE(vr.distance, 1.0) as vector_distance,
       COALESCE(tr.rank, 0.0) as text_rank,
       (COALESCE(1 - vr.distance, 0) * 0.7 + COALESCE(tr.rank, 0) * 0.3) as combined_score
FROM documents d
LEFT JOIN vector_results vr ON d.id = vr.document_id
LEFT JOIN text_results tr ON d.id = tr.document_id
WHERE vr.document_id IS NOT NULL OR tr.document_id IS NOT NULL
ORDER BY combined_score DESC
LIMIT 10;
```

### Multi-Model Embeddings

Store embeddings from multiple providers for comparison:

```ruby
providers = [
  { client: Prescient.client(:ollama), name: 'ollama', model: 'nomic-embed-text', dims: 768 },
  { client: Prescient.client(:openai), name: 'openai', model: 'text-embedding-3-small', dims: 1536 }
]

providers.each do |provider|
  next unless provider[:client].available?

  embedding = provider[:client].generate_embedding(text)
  vector_str = "[#{embedding.join(',')}]"

  db.exec_params(
    "INSERT INTO document_embeddings (document_id, embedding_provider, embedding_model, embedding_dimensions, embedding, embedding_text) VALUES ($1, $2, $3, $4, $5, $6)",
    [document_id, provider[:name], provider[:model], provider[:dims], vector_str, text]
  )
end
```

## Monitoring and Analytics

### Search Performance Tracking

```ruby
# Track search queries and results
def track_search(query_text, results, provider, model)
  query_embedding = client.generate_embedding(query_text)
  query_vector = "[#{query_embedding.join(',')}]"

  # Insert search query
  query_result = db.exec_params(
    "INSERT INTO search_queries (query_text, embedding_provider, embedding_model, query_embedding, result_count) VALUES ($1, $2, $3, $4, $5) RETURNING id",
    [query_text, provider, model, query_vector, results.length]
  )
  query_id = query_result[0]['id']

  # Insert query results
  results.each_with_index do |result, index|
    db.exec_params(
      "INSERT INTO query_results (query_id, document_id, similarity_score, rank_position) VALUES ($1, $2, $3, $4)",
      [query_id, result['document_id'], result['similarity_score'], index + 1]
    )
  end
end
```

### Analytics Queries

```sql
-- Popular search terms
SELECT query_text, COUNT(*) as search_count
FROM search_queries
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY query_text
ORDER BY search_count DESC
LIMIT 10;

-- Average similarity scores
SELECT embedding_provider, embedding_model,
       AVG(similarity_score) as avg_similarity,
       COUNT(*) as result_count
FROM query_results qr
JOIN search_queries sq ON qr.query_id = sq.id
GROUP BY embedding_provider, embedding_model;

-- Search performance over time
SELECT DATE_TRUNC('hour', created_at) as hour,
       COUNT(*) as searches,
       AVG(result_count) as avg_results
FROM search_queries
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour;
```

## Troubleshooting

### Common Issues

**Slow queries:**

```sql
-- Check if indexes are being used
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM document_embeddings
ORDER BY embedding <=> '[...]'::vector
LIMIT 10;

-- Rebuild indexes if needed
REINDEX INDEX idx_document_embeddings_cosine;
```

**Memory issues:**

```sql
-- Check index sizes
SELECT schemaname, tablename, indexname, pg_size_pretty(pg_relation_size(indexrelid)) as size
FROM pg_stat_user_indexes
WHERE tablename LIKE '%embedding%'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Adjust work_mem for index building
SET work_mem = '256MB';
```

**Dimension mismatches:**

```ruby
# Validate embedding dimensions before storing
expected_dims = 768
if embedding.length != expected_dims
  raise "Expected #{expected_dims} dimensions, got #{embedding.length}"
end
```

## Best Practices

1. **Choose appropriate chunk sizes** based on your content and use case
2. **Monitor query performance** and adjust indexes as needed
3. **Use metadata filtering** to improve search relevance
4. **Implement caching** for frequently accessed embeddings
5. **Regular maintenance** of vector indexes for optimal performance
6. **Test different distance functions** to find what works best for your data
7. **Consider hybrid search** combining vector and text search for better results

## Resources

- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [HNSW Algorithm](https://arxiv.org/abs/1603.09320)
- [Vector Database Concepts](https://www.pinecone.io/learn/vector-database/)
- [Embedding Best Practices](https://platform.openai.com/docs/guides/embeddings/what-are-embeddings)
