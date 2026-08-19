# frozen_string_literal: true

require 'json'

# rubocop:disable Style/ClassAndModuleChildren
module Prescient
  # Bounded sources of JSON documents suitable for generation context.
  module DocumentSource
    # @return [Integer] Default maximum number of documents
    DEFAULT_MAX_DOCUMENTS = 100
    # @return [Integer] Default maximum serialized source size
    DEFAULT_MAX_BYTES = 1_048_576

    # Common validation and size-bound behavior for document sources.
    class Base
      def initialize(max_documents: DEFAULT_MAX_DOCUMENTS, max_bytes: DEFAULT_MAX_BYTES)
        @max_documents = positive_integer(max_documents, 'max_documents')
        @max_bytes = positive_integer(max_bytes, 'max_bytes')
      end

      # @return [Array<Hash>] JSON object documents
      def fetch
        raise NotImplementedError
      end

      private

      def normalize(value)
        documents = value.is_a?(Array) ? value : [value]
        raise Prescient::Error, 'document source must contain JSON objects' unless documents.all?(Hash)
        if documents.length > @max_documents
          raise Prescient::Error, "document source cannot contain more than #{@max_documents} documents"
        end

        serialized = JSON.generate(documents)
        raise Prescient::Error, "document source exceeds #{@max_bytes} bytes" if serialized.bytesize > @max_bytes

        documents
      end

      def parse_json(value)
        normalize(JSON.parse(value))
      rescue JSON::ParserError => e
        raise Prescient::Error, "document source contains invalid JSON: #{e.message}"
      end

      def positive_integer(value, name)
        return value if value.is_a?(Integer) && value.positive?

        raise Prescient::Error, "#{name} must be a positive integer"
      end
    end

    # Validate and bound application-provided JSON documents.
    class Memory < Base
      # @param documents [Array<Hash>, Hash] Documents to validate
      def initialize(documents:, **options)
        super(**options)
        @documents = documents
      end

      # @return [Array<Hash>] Validated documents
      def fetch
        normalize(@documents)
      end
    end

    # Read JSON documents from a local file.
    class JsonFile < Base
      # @param path [String] JSON file path
      def initialize(path:, **options)
        super(**options)
        @path = path
        return if @path.is_a?(String) && !@path.empty?

        raise Prescient::Error, 'document source path must be a non-empty string'
      end

      # @return [Array<Hash>] Documents loaded from the file
      def fetch
        raise Prescient::Error, "document source file not found: #{@path}" unless File.file?(@path)
        raise Prescient::Error, "document source file exceeds #{@max_bytes} bytes" if File.size(@path) > @max_bytes

        parse_json(File.read(@path))
      rescue Errno::EACCES => e
        raise Prescient::Error, "unable to read document source: #{e.message}"
      end
    end

    # Read JSON documents from a Redis-compatible client.
    # The client is injected to keep Redis optional for gem consumers.
    class RedisJson < Base
      # @param client [#get] Redis-compatible client
      # @param key [String] Redis key containing a JSON document or array
      def initialize(client:, key:, **options)
        super(**options)
        @client = client
        @key = key
        return if @key.is_a?(String) && !@key.empty?

        raise Prescient::Error, 'Redis document key must be a non-empty string'
      end

      # @return [Array<Hash>] Documents loaded from Redis
      def fetch
        value = @client.get(@key)
        raise Prescient::Error, "Redis document source key not found: #{@key}" unless value

        parse_json(value)
      rescue NoMethodError
        raise Prescient::Error, 'Redis document source client must provide get'
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
