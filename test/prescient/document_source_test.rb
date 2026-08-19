# frozen_string_literal: true

require 'test_helper'
require 'tempfile'

class DocumentSourceTest < PrescientTest
  def test_json_file_loads_an_array_of_objects
    file = Tempfile.new(['documents', '.json'])
    file.write(JSON.generate([{ 'title' => 'One' }, { 'title' => 'Two' }]))
    file.close

    assert_equal [{ 'title' => 'One' }, { 'title' => 'Two' }],
                 Prescient::DocumentSource::JsonFile.new(path: file.path).fetch
  ensure
    file&.unlink
  end

  def test_json_file_accepts_one_object_and_enforces_limits
    file = Tempfile.new(['document', '.json'])
    file.write(JSON.generate('title' => 'One'))
    file.close

    source = Prescient::DocumentSource::JsonFile.new(path: file.path, max_documents: 1)

    assert_equal [{ 'title' => 'One' }], source.fetch
    assert_raises(Prescient::Error) do
      Prescient::DocumentSource::JsonFile.new(path: file.path, max_bytes: 1).fetch
    end
  ensure
    file&.unlink
  end

  def test_redis_source_uses_an_injected_client
    client = Struct.new(:value) { def get(_key) = value }.new(JSON.generate([{ 'id' => 1 }]))

    assert_equal [{ 'id' => 1 }],
                 Prescient::DocumentSource::RedisJson.new(client:, key: 'docs').fetch
  end

  def test_sources_reject_invalid_json_and_non_objects
    assert_raises(Prescient::Error) do
      Prescient::DocumentSource::Memory.new(documents: ['invalid']).fetch
    end
    assert_raises(Prescient::Error) do
      Prescient::DocumentSource::Memory.new(documents: '{invalid').fetch
    end
  end

  def test_sources_reject_invalid_limits_and_missing_values
    assert_raises(Prescient::Error) do
      Prescient::DocumentSource::Memory.new(documents: [], max_documents: 0)
    end
    assert_raises(Prescient::Error) do
      Prescient::DocumentSource::Memory.new(documents: [], max_bytes: 0)
    end
    assert_raises(Prescient::Error) do
      Prescient::DocumentSource::Memory.new(documents: [{ id: 1 }, { id: 2 }], max_documents: 1).fetch
    end
    assert_raises(Prescient::Error) do
      Prescient::DocumentSource::JsonFile.new(path: '').fetch
    end
    assert_raises(Prescient::Error) do
      Prescient::DocumentSource::JsonFile.new(path: '/missing/docs.json').fetch
    end
    assert_raises(Prescient::Error) do
      Prescient::DocumentSource::RedisJson.new(client: Object.new, key: 'docs').fetch
    end
    assert_raises(Prescient::Error) { Prescient::DocumentSource::RedisJson.new(client: Struct.new(:value) { def get(*) = nil }.new, key: 'docs').fetch }
  end

  def test_redis_source_rejects_invalid_json_and_keys
    client = Struct.new(:value) { def get(*) = value }.new('{invalid')

    assert_raises(Prescient::Error) do
      Prescient::DocumentSource::RedisJson.new(client:, key: '').fetch
    end
    assert_raises(Prescient::Error) { Prescient::DocumentSource::RedisJson.new(client:, key: 'docs').fetch }
  end
end
