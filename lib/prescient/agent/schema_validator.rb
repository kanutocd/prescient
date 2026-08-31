# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Validates the JSON-schema subset used by agent tools.
  # rubocop:disable Metrics/ClassLength
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
      validate_schema(@schema, value, [])
      value
    end

    private

    def validate_schema(schema, value, path)
      schema = resolve_reference(schema)
      validate_composition(schema, value, path)
      validate_enum(schema, value, path)
      validate_type(schema, value, path)
      validate_string_constraints(schema, value, path)
      validate_number_constraints(schema, value, path)
      validate_array_constraints(schema, value, path)
      validate_object_constraints(schema, value, path)
    end

    def validate_composition(schema, value, path)
      schemas = schema_value(schema, "oneOf")
      return unless schemas

      matches = schemas.count do |candidate|
        validate_schema(candidate, value, path)
        true
      rescue MalformedActionError
        false
      end
      return if matches == 1

      raise MalformedActionError, "agent tool arguments must match exactly one schema#{path_suffix(path)}"
    end

    def validate_enum(schema, value, path)
      values = schema_value(schema, "enum")
      return unless values
      return if values.include?(value)

      raise MalformedActionError, "agent tool argument is not an allowed value#{path_suffix(path)}"
    end

    def validate_type(schema, value, path)
      type = schema_value(schema, "type")
      return unless type

      valid = {
        "object" => value.is_a?(Hash),
        "array" => value.is_a?(Array),
        "string" => value.is_a?(String),
        "integer" => value.is_a?(Integer),
        "number" => value.is_a?(Numeric) && !value.is_a?(Complex),
        "boolean" => [true, false].include?(value)
      }.fetch(type.to_s, false)
      return if valid

      raise MalformedActionError, "agent tool arguments must be a #{type}#{path_suffix(path)}"
    end

    def validate_string_constraints(schema, value, path)
      return unless value.is_a?(String)

      minimum = schema_value(schema, "minLength")
      maximum = schema_value(schema, "maxLength")
      pattern = schema_value(schema, "pattern")
      if minimum && value.length < minimum
        raise MalformedActionError, "agent string is shorter than allowed#{path_suffix(path)}"
      end
      if maximum && value.length > maximum
        raise MalformedActionError, "agent string is longer than allowed#{path_suffix(path)}"
      end
      return unless pattern && !Regexp.new(pattern).match?(value)

      raise MalformedActionError, "agent string does not match the required pattern#{path_suffix(path)}"
    rescue RegexpError
      raise ConfigurationError, "agent tool schema contains an invalid pattern"
    end

    def validate_number_constraints(schema, value, path)
      return unless value.is_a?(Numeric) && !value.is_a?(Complex)

      minimum = schema_value(schema, "minimum")
      maximum = schema_value(schema, "maximum")
      exclusive_minimum = schema_value(schema, "exclusiveMinimum")
      exclusive_maximum = schema_value(schema, "exclusiveMaximum")
      validate_lower_bound(value, minimum, path)
      validate_upper_bound(value, maximum, path)
      validate_lower_bound(value, exclusive_minimum, path, exclusive: true)
      validate_upper_bound(value, exclusive_maximum, path, exclusive: true)
    end

    def validate_array_constraints(schema, value, path)
      return unless value.is_a?(Array)

      minimum = schema_value(schema, "minItems")
      maximum = schema_value(schema, "maxItems")
      if minimum && value.length < minimum
        raise MalformedActionError, "agent array has too few items#{path_suffix(path)}"
      end
      if maximum && value.length > maximum
        raise MalformedActionError, "agent array has too many items#{path_suffix(path)}"
      end

      item_schema = schema_value(schema, "items")
      return unless item_schema.is_a?(Hash)

      value.each_with_index { |item, index| validate_schema(item_schema, item, path + [index]) }
    end

    def validate_object_constraints(schema, value, path)
      return unless value.is_a?(Hash)

      validate_required(value, schema, path)
      validate_properties(value, schema, path)
      validate_additional_properties(value, schema, path)
    end

    def validate_required(value, schema, path)
      (schema_value(schema, "required") || []).each do |key|
        next if value.key?(key) || value.key?(key.to_sym)

        raise MalformedActionError, "agent tool arguments missing: #{key}#{path_suffix(path)}"
      end
    end

    def validate_properties(value, schema, path)
      (schema_value(schema, "properties") || {}).each do |key, property_schema|
        next unless value.key?(key) || value.key?(key.to_sym)

        property_value = value.key?(key) ? value[key] : value[key.to_sym]
        validate_schema(property_schema, property_value, path + [key])
      end
    end

    def validate_additional_properties(value, schema, path)
      return unless schema_value(schema, "additionalProperties") == false

      property_names = (schema_value(schema, "properties") || {}).keys.map(&:to_s)
      value.each_key do |key|
        next if property_names.include?(key.to_s)

        raise MalformedActionError, "agent tool arguments not allowed: #{key}#{path_suffix(path)}"
      end
    end

    def validate_lower_bound(value, bound, path, exclusive: false)
      return unless bound.is_a?(Numeric)
      return if exclusive ? value > bound : value >= bound

      description = exclusive ? "exclusive minimum" : "minimum"
      raise MalformedActionError, "agent number is below the #{description}#{path_suffix(path)}"
    end

    def validate_upper_bound(value, bound, path, exclusive: false)
      return unless bound.is_a?(Numeric)
      return if exclusive ? value < bound : value <= bound

      description = exclusive ? "exclusive maximum" : "maximum"
      raise MalformedActionError, "agent number exceeds the #{description}#{path_suffix(path)}"
    end

    def resolve_reference(schema)
      reference = schema_value(schema, "$ref")
      return schema unless reference
      return resolve_pointer(reference) if reference.start_with?("#/")

      raise ConfigurationError, "agent tool schema only supports local $ref values"
    end

    def resolve_pointer(reference)
      reference.delete_prefix("#/").split("/").reduce(@schema) do |current, token|
        key = token.gsub("~1", "/").gsub("~0", "~")
        current.fetch(key) { current.fetch(key.to_sym) }
      end
    rescue KeyError, NoMethodError
      raise ConfigurationError, "agent tool schema contains an unresolved $ref"
    end

    def schema_value(schema, key)
      return schema[key] if schema.key?(key)
      return schema[key.to_sym] if schema.key?(key.to_sym)

      nil
    end

    def path_suffix(path)
      return "" if path.empty?

      " at #{path.map { |part| part.is_a?(Integer) ? "[#{part}]" : part }.join(".")}"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
# rubocop:enable Style/ClassAndModuleChildren
