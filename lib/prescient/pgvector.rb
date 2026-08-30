# frozen_string_literal: true

require "json"

module Prescient
  module Pgvector
    # PostgreSQL pgvector integration.
    #
    # The integration accepts a PG-compatible connection object, so applications
    # choose and manage their own PostgreSQL driver and connection lifecycle.
    # Stores provider embeddings and performs nearest-neighbor searches.
    class Store
      # @return [Hash<Symbol, String>] Supported pgvector distance operators
      METRICS = {
        cosine: "<=>",
        euclidean: "<->",
        inner_product: "<#>"
      }.freeze

      # @return [Integer] Required vector dimensions
      attr_reader :dimensions

      # @return [String] Embeddings table name
      attr_reader :table

      # @param connection [Object] PG-compatible object responding to `exec`
      #   and `exec_params`
      # @param dimensions [Integer] Required dimensions for every embedding
      # @param table [String, Symbol] Safe PostgreSQL table identifier
      def initialize(connection:, dimensions:, table: "prescient_embeddings")
        @connection = connection
        @dimensions = validate_dimensions(dimensions)
        @table = validate_table(table)
      end

      # Create the pgvector extension and the embeddings table.
      #
      # @return [void]
      def install!
        @connection.exec("CREATE EXTENSION IF NOT EXISTS vector")
        @connection.exec(<<~SQL)
          CREATE TABLE IF NOT EXISTS #{table} (
            id text PRIMARY KEY,
            provider text NOT NULL,
            model text NOT NULL,
            dimensions integer NOT NULL CHECK (dimensions = #{dimensions}),
            embedding vector(#{dimensions}) NOT NULL,
            content text,
            metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
            created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
          )
        SQL
      end

      # Create an HNSW index for the selected distance metric.
      #
      # @param metric [Symbol] `:cosine`, `:euclidean`, or `:inner_product`
      # @return [void]
      def create_index!(metric: :cosine)
        metric_name = validate_metric(metric)
        @connection.exec(<<~SQL)
          CREATE INDEX IF NOT EXISTS #{table}_#{metric_name}_embedding_idx
          ON #{table} USING hnsw (embedding #{metric_operator_class(metric_name)})
        SQL
      end

      # Insert or replace an embedding record.
      #
      # @return [Hash] Stored record metadata
      def upsert(id:, embedding:, provider:, model:, content: nil, metadata: {})
        vector = serialize_vector(embedding)
        parameters = [id.to_s, provider.to_s, model.to_s, dimensions, vector, content, JSON.generate(metadata)]
        result = @connection.exec_params(<<~SQL, parameters)
          INSERT INTO #{table} (id, provider, model, dimensions, embedding, content, metadata)
          VALUES ($1, $2, $3, $4, $5::vector, $6, $7::jsonb)
          ON CONFLICT (id) DO UPDATE SET
            provider = EXCLUDED.provider,
            model = EXCLUDED.model,
            dimensions = EXCLUDED.dimensions,
            embedding = EXCLUDED.embedding,
            content = EXCLUDED.content,
            metadata = EXCLUDED.metadata,
            updated_at = CURRENT_TIMESTAMP
          RETURNING id, provider, model, dimensions, content, metadata
        SQL

        record_from(result.first)
      end

      # Find the nearest stored embeddings.
      #
      # @param embedding [Array<Numeric>] Query vector
      # @param limit [Integer] Maximum result count
      # @param metric [Symbol] Distance metric
      # @param provider [String, Symbol, nil] Optional provider filter
      # @param model [String, nil] Optional model filter
      # @return [Array<Hash>] Records ordered by ascending distance
      def search(embedding:, limit: 10, metric: :cosine, provider: nil, model: nil)
        vector = serialize_vector(embedding)
        limit = validate_limit(limit)
        metric = validate_metric(metric)
        filters, parameters = search_filters(provider, model)
        result = @connection.exec_params(search_query(metric, filters), [vector, limit, *parameters])

        result.map { |row| record_from(row) }
      end

      private

      def validate_dimensions(value)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "dimensions must be a positive integer"
      end

      def validate_table(value)
        table = value.to_s
        return table if /\A[a-z_][a-z0-9_]*\z/.match?(table)

        raise ArgumentError, "table must be a lowercase PostgreSQL identifier"
      end

      def serialize_vector(embedding)
        unless embedding.is_a?(Array) && embedding.length == dimensions
          raise Prescient::InvalidVectorError, "embedding must contain exactly #{dimensions} values"
        end

        values = embedding.map { |value| Float(value) }
        raise Prescient::InvalidVectorError, "embedding values must be finite" unless values.all?(&:finite?)

        "[#{values.join(",")}]"
      rescue ArgumentError, TypeError
        raise Prescient::InvalidVectorError, "embedding values must be numeric"
      end

      def validate_limit(value)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "limit must be a positive integer"
      end

      def validate_metric(value)
        return value if METRICS.key?(value)

        raise ArgumentError, "unsupported distance metric: #{value}"
      end

      def metric_operator_class(metric)
        {
          cosine: "vector_cosine_ops",
          euclidean: "vector_l2_ops",
          inner_product: "vector_ip_ops"
        }.fetch(metric)
      end

      def search_filters(provider, model)
        filters = []
        parameters = []
        if provider
          filters << "provider = $#{parameters.length + 3}"
          parameters << provider.to_s
        end
        if model
          filters << "model = $#{parameters.length + 3}"
          parameters << model
        end

        [filters, parameters]
      end

      def search_query(metric, filters)
        where = filters.empty? ? "" : "WHERE #{filters.join(" AND ")}"

        <<~SQL
          SELECT id, provider, model, dimensions, content, metadata,
                 embedding #{METRICS.fetch(metric)} $1::vector AS distance
          FROM #{table}
          #{where}
          ORDER BY embedding #{METRICS.fetch(metric)} $1::vector
          LIMIT $2
        SQL
      end

      def record_from(row)
        {
          id: row.fetch("id"),
          provider: row.fetch("provider"),
          model: row.fetch("model"),
          dimensions: Integer(row.fetch("dimensions")),
          content: row.fetch("content"),
          metadata: JSON.parse(row.fetch("metadata")),
          distance: row["distance"]&.to_f
        }
      end
    end
  end
end
