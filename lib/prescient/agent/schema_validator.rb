# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Validates the JSON-schema subset used by agent tools.
  class SchemaValidator
    # Validate a value against a schema.
    # @param schema [Hash] Supported JSON-schema subset
    # @param value [Object] Value to validate
    # @return [Object] The validated value
    def self.validate!(schema, value)
      new(schema).validate!(value)
    end

    def initialize(schema)
      @schema = schema.is_a?(Hash) ? schema : {}
    end

    # Validate a value against this validator's schema.
    # @param value [Object] Value to validate
    # @return [Object] The validated value
    def validate!(value)
      validate_type(value)
      validate_required(value)
      validate_properties(value)
      validate_additional_properties(value)
      value
    end

    private

    def validate_type(value)
      type = @schema["type"] || @schema[:type]
      return unless type

      valid = {
        "object" => value.is_a?(Hash),
        "array" => value.is_a?(Array),
        "string" => value.is_a?(String),
        "integer" => value.is_a?(Integer),
        "number" => value.is_a?(Numeric),
        "boolean" => [true, false].include?(value)
      }.fetch(type.to_s, false)
      raise MalformedActionError, "agent tool arguments must be a #{type}" unless valid
    end

    def validate_required(value)
      required = @schema["required"] || @schema[:required] || []
      return unless value.is_a?(Hash)

      required.each do |key|
        next if value.key?(key) || value.key?(key.to_sym)

        raise MalformedActionError, "agent tool arguments missing: #{key}"
      end
    end

    def validate_properties(value)
      return unless value.is_a?(Hash)

      properties = @schema["properties"] || @schema[:properties] || {}
      properties.each do |key, schema|
        next unless value.key?(key) || value.key?(key.to_sym)

        property_value = value.key?(key) ? value[key] : value[key.to_sym]
        self.class.validate!(schema, property_value)
      end
    end

    def validate_additional_properties(value)
      return unless value.is_a?(Hash)
      return unless (@schema["additionalProperties"] || @schema[:additionalProperties]) == false

      properties = (@schema["properties"] || @schema[:properties] || {}).keys.map(&:to_s)
      value.each_key do |key|
        next if properties.include?(key.to_s)

        raise MalformedActionError, "agent tool arguments not allowed: #{key}"
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
