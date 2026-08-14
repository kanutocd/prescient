# frozen_string_literal: true

require 'test_helper'

class PgvectorStoreTest < PrescientTest
  RECORD = {
    'id'         => 'document-1',
    'provider'   => 'openai',
    'model'      => 'text-embedding-3-small',
    'dimensions' => '3',
    'content'    => 'Ruby is expressive.',
    'metadata'   => '{"topic":"ruby"}',
  }.freeze

  def setup
    super
    @connection = mock('connection')
    @store = Prescient::Pgvector::Store.new(connection: @connection, dimensions: 3)
  end

  def test_initialization_validates_dimensions_and_table_name
    assert_equal 3, @store.dimensions
    assert_equal 'prescient_embeddings', @store.table

    assert_raises(ArgumentError) do
      Prescient::Pgvector::Store.new(connection: @connection, dimensions: 0)
    end
    assert_raises(ArgumentError) do
      Prescient::Pgvector::Store.new(connection: @connection, dimensions: '3')
    end
    assert_raises(ArgumentError) do
      Prescient::Pgvector::Store.new(connection: @connection, dimensions: 3, table: 'items; DROP TABLE items')
    end
  end

  def test_install_creates_extension_and_dimensioned_table
    @connection.expects(:exec).with('CREATE EXTENSION IF NOT EXISTS vector')
    @connection.expects(:exec).with do |sql|
      sql.include?('CREATE TABLE IF NOT EXISTS prescient_embeddings') &&
        sql.include?('embedding vector(3) NOT NULL') &&
        sql.include?('CHECK (dimensions = 3)')
    end

    @store.install!
  end

  def test_create_index_supports_each_metric
    {
      cosine:        'vector_cosine_ops',
      euclidean:     'vector_l2_ops',
      inner_product: 'vector_ip_ops',
    }.each do |metric, operator_class|
      @connection.expects(:exec).with do |sql|
        sql.include?("prescient_embeddings_#{metric}_embedding_idx") && sql.include?(operator_class)
      end

      @store.create_index!(metric:)
    end

    assert_raises(ArgumentError) { @store.create_index!(metric: :manhattan) }
  end

  def test_upsert_serializes_vectors_and_normalizes_the_returned_record
    @connection.expects(:exec_params).with { |sql, parameters|
      sql.include?('INSERT INTO prescient_embeddings') &&
        parameters == ['document-1', 'openai', 'text-embedding-3-small', 3, '[1.0,2.5,3.0]', 'Ruby is expressive.', '{"topic":"ruby"}']
    }.returns([RECORD])

    result = @store.upsert(
      id:        'document-1',
      embedding: [1, 2.5, '3'],
      provider:  :openai,
      model:     'text-embedding-3-small',
      content:   'Ruby is expressive.',
      metadata:  { topic: 'ruby' },
    )

    assert_equal(
      {
        id:         'document-1',
        provider:   'openai',
        model:      'text-embedding-3-small',
        dimensions: 3,
        content:    'Ruby is expressive.',
        metadata:   { 'topic' => 'ruby' },
        distance:   nil,
      },
      result,
    )
  end

  def test_search_uses_parameterized_filters_and_selected_metric
    row = RECORD.merge('distance' => '0.25')
    @connection.expects(:exec_params).with { |sql, parameters|
      sql.include?('embedding <#> $1::vector AS distance') &&
        sql.include?('WHERE provider = $3 AND model = $4') &&
        parameters == ['[1.0,2.0,3.0]', 5, 'openai', 'text-embedding-3-small']
    }.returns([row])

    result = @store.search(
      embedding: [1, 2, 3],
      limit:     5,
      metric:    :inner_product,
      provider:  :openai,
      model:     'text-embedding-3-small',
    )

    assert_in_delta(0.25, result.first[:distance])
  end

  def test_search_without_filters_uses_cosine_distance
    @connection.expects(:exec_params).with { |sql, parameters|
      sql.include?('embedding <=> $1::vector AS distance') && !sql.include?('WHERE') &&
        parameters == ['[1.0,2.0,3.0]', 10]
    }.returns([])

    assert_empty @store.search(embedding: [1, 2, 3])
  end

  def test_vectors_must_match_dimensions_and_contain_finite_numbers
    assert_raises(Prescient::InvalidVectorError) do
      @store.search(embedding: [1, 2])
    end
    assert_raises(Prescient::InvalidVectorError) do
      @store.search(embedding: [1, 2, 'invalid'])
    end
    assert_raises(Prescient::InvalidVectorError) do
      @store.search(embedding: [1, 2, Float::INFINITY])
    end
  end

  def test_search_validates_limits_and_metrics
    assert_raises(ArgumentError) do
      @store.search(embedding: [1, 2, 3], limit: 0)
    end
    assert_raises(ArgumentError) do
      @store.search(embedding: [1, 2, 3], limit: '10')
    end
    assert_raises(ArgumentError) do
      @store.search(embedding: [1, 2, 3], metric: :manhattan)
    end
  end
end
