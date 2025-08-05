# frozen_string_literal: true

# Base class for all AI provider implementations
#
# This abstract base class defines the common interface that all AI providers
# must implement. It provides shared functionality for text processing, context
# formatting, prompt building, and error handling.
#
# @abstract Subclass and implement {#generate_embedding}, {#generate_response},
#   {#health_check}, and {#validate_configuration!}
#
# @example Creating a custom provider
#   class MyProvider < Prescient::Base
#     def generate_embedding(text, **options)
#       # Implementation here
#     end
#
#     def generate_response(prompt, context_items = [], **options)
#       # Implementation here
#     end
#
#     def health_check
#       # Implementation here
#     end
#   end
#
# @author Claude Code
# @since 1.0.0
class Prescient::Base
  # @return [Hash] Configuration options for this provider instance
  attr_reader :options

  # Initialize the provider with configuration options
  #
  # @param options [Hash] Provider-specific configuration options
  # @option options [String] :api_key API key for authenticated providers
  # @option options [String] :url Base URL for self-hosted providers
  # @option options [Integer] :timeout Request timeout in seconds
  # @option options [Hash] :prompt_templates Custom prompt templates
  # @option options [Hash] :context_configs Context formatting configurations
  def initialize(**options)
    @options = options
    validate_configuration!
  end

  # Generate embeddings for the given text
  #
  # This method must be implemented by subclasses to provide embedding
  # generation functionality.
  #
  # @param text [String] The text to generate embeddings for
  # @param options [Hash] Provider-specific options
  # @return [Array<Float>] Array of embedding values
  # @raise [NotImplementedError] If not implemented by subclass
  # @abstract
  def generate_embedding(text, **options)
    raise NotImplementedError, "#{self.class} must implement #generate_embedding"
  end

  # Generate text response for the given prompt
  #
  # This method must be implemented by subclasses to provide text generation
  # functionality with optional context items.
  #
  # @param prompt [String] The prompt to generate a response for
  # @param context_items [Array<Hash, String>] Optional context items to include
  # @param options [Hash] Provider-specific generation options
  # @option options [Float] :temperature Sampling temperature (0.0-2.0)
  # @option options [Integer] :max_tokens Maximum tokens to generate
  # @option options [Float] :top_p Nucleus sampling parameter
  # @return [Hash] Response hash with :response, :model, :provider keys
  # @raise [NotImplementedError] If not implemented by subclass
  # @abstract
  def generate_response(prompt, context_items = [], **options)
    raise NotImplementedError, "#{self.class} must implement #generate_response"
  end

  # Check the health and availability of the provider
  #
  # This method must be implemented by subclasses to provide health check
  # functionality.
  #
  # @return [Hash] Health status with :status, :provider keys and optional details
  # @raise [NotImplementedError] If not implemented by subclass
  # @abstract
  def health_check
    raise NotImplementedError, "#{self.class} must implement #health_check"
  end

  # Check if the provider is currently available
  #
  # @return [Boolean] true if provider is healthy and available
  def available?
    health_check[:status] == 'healthy'
  rescue StandardError
    false
  end

  protected

  # Validate provider configuration
  #
  # Override this method in subclasses to validate required configuration
  # options and raise appropriate errors for missing or invalid settings.
  #
  # @return [void]
  # @raise [Prescient::Error] If configuration is invalid
  def validate_configuration!
    # Override in subclasses to validate required configuration
  end

  # Handle and standardize errors from provider operations
  #
  # Wraps provider-specific operations and converts common exceptions
  # into standardized Prescient error types while preserving existing
  # Prescient errors.
  #
  # @yield The operation block to execute with error handling
  # @return [Object] The result of the yielded block
  # @raise [Prescient::ConnectionError] For network/timeout errors
  # @raise [Prescient::InvalidResponseError] For JSON parsing errors
  # @raise [Prescient::Error] For other unexpected errors
  def handle_errors
    yield
  rescue Prescient::Error
    # Re-raise Prescient errors without wrapping
    raise
  rescue Net::ReadTimeout, Net::OpenTimeout => e
    raise Prescient::ConnectionError, "Request timeout: #{e.message}"
  rescue Net::HTTPError => e
    raise Prescient::ConnectionError, "HTTP error: #{e.message}"
  rescue JSON::ParserError => e
    raise Prescient::InvalidResponseError, "Invalid JSON response: #{e.message}"
  rescue StandardError => e
    raise Prescient::Error, "Unexpected error: #{e.message}"
  end

  # Normalize embedding dimensions to match expected size
  #
  # Ensures embedding vectors have consistent dimensions by truncating
  # longer vectors or padding shorter ones with zeros.
  #
  # @param embedding [Array<Float>] The embedding vector to normalize
  # @param target_dimensions [Integer] The desired number of dimensions
  # @return [Array<Float>, nil] Normalized embedding or nil if input invalid
  def normalize_embedding(embedding, target_dimensions)
    return nil unless embedding.is_a?(Array)
    return embedding.first(target_dimensions) if embedding.length >= target_dimensions

    embedding + Array.new(target_dimensions - embedding.length, 0.0)
  end

  # Clean and preprocess text for AI processing
  #
  # Removes excess whitespace, normalizes spacing, and enforces length
  # limits suitable for most AI models.
  #
  # @param text [String, nil] The text to clean
  # @return [String] Cleaned text, empty string if input was nil/empty
  def clean_text(text)
    # Limit length for most models
    text.to_s.gsub(/\s+/, ' ').strip.slice(0, 8000)
  end

  # Get default prompt templates
  #
  # Provides standard templates for system prompts and context handling
  # that can be overridden via provider options.
  #
  # @return [Hash] Hash containing template strings with placeholders
  # @private
  def default_prompt_templates
    {
      system_prompt:         'You are a helpful AI assistant. Answer questions clearly and accurately.',
      no_context_template:   <<~TEMPLATE.strip,
        %<system_prompt>s

        Question: %<query>s

        Please provide a helpful response based on your knowledge.
      TEMPLATE
      with_context_template: <<~TEMPLATE.strip,
        %<system_prompt>s Use the following context to answer the question. If the context doesn't contain relevant information, say so clearly.

        Context:
        %<context>s

        Question: %<query>s

        Please provide a helpful response based on the context above.
      TEMPLATE
    }
  end

  # Build formatted prompt from query and context items
  #
  # Creates a properly formatted prompt using configurable templates,
  # incorporating context items when provided.
  #
  # @param query [String] The user's question or prompt
  # @param context_items [Array<Hash, String>] Optional context items
  # @return [String] Formatted prompt ready for AI processing
  def build_prompt(query, context_items = [])
    templates = default_prompt_templates.merge(@options[:prompt_templates] || {})
    system_prompt = templates[:system_prompt]

    if context_items.empty?
      templates[:no_context_template] % {
        system_prompt: system_prompt,
        query:         query,
      }
    else
      context_text = context_items.map.with_index(1) { |item, index|
        "#{index}. #{format_context_item(item)}"
      }.join("\n\n")

      templates[:with_context_template] % {
        system_prompt: system_prompt,
        context:       context_text,
        query:         query,
      }
    end
  end

  # Minimal default context configuration - users should define their own contexts
  def default_context_configs
    {
      # Generic fallback configuration - works with any hash structure
      'default' => {
        fields:           [], # Will be dynamically determined from item keys
        format:           nil, # Will use fallback formatting
        embedding_fields: [], # Will use all string/text fields
      },
    }
  end

  # Extract text for embedding generation based on context configuration
  def extract_embedding_text(item, context_type = nil)
    return item.to_s unless item.is_a?(Hash)

    config = resolve_context_config(item, context_type)
    text_values = extract_configured_fields(item, config) || extract_text_values(item)
    text_values.join(' ').strip
  end

  # Extract text values from hash, excluding non-textual fields
  def extract_text_values(item)
    # Common fields to exclude from embedding text
    # TODO: configurable fields to exclude aside from the common ones below
    exclude_fields = ['id', '_id', 'uuid', 'created_at', 'updated_at', 'timestamp', 'version', 'status', 'active']

    item.filter_map { |key, value|
      next if exclude_fields.include?(key.to_s.downcase)
      next unless value.is_a?(String) || value.is_a?(Numeric)
      next if value.to_s.strip.empty?

      value.to_s
    }
  end

  # Generic context item formatting using configurable contexts
  def format_context_item(item)
    case item
    when Hash then format_hash_item(item)
    when String then item
    else item.to_s
    end
  end

  private

  # Resolve context configuration for an item
  def resolve_context_config(item, context_type)
    context_configs = default_context_configs.merge(@options[:context_configs] || {})
    return context_configs['default'] if context_configs.empty?

    detected_type = context_type || detect_context_type(item)
    context_configs[detected_type] || context_configs['default']
  end

  # Extract fields configured for embeddings
  def extract_configured_fields(item, config)
    return nil unless config[:embedding_fields]&.any?

    config[:embedding_fields].filter_map { |field| item[field] || item[field.to_sym] }
  end

  # Format a hash item using context configuration
  def format_hash_item(item)
    config = resolve_context_config(item, nil)
    return fallback_format_hash(item) unless config[:format]

    format_data = build_format_data(item, config)
    return fallback_format_hash(item) unless format_data.any?

    apply_format_template(config[:format], format_data) || fallback_format_hash(item)
  end

  # Build format data from item fields
  def build_format_data(item, config)
    format_data = {}
    fields_to_check = config[:fields].any? ? config[:fields] : item.keys.map(&:to_s)

    fields_to_check.each do |field|
      value = item[field] || item[field.to_sym]
      format_data[field.to_sym] = value if value
    end

    format_data
  end

  # Apply format template with error handling
  def apply_format_template(template, format_data)
    template % format_data
  rescue KeyError
    nil
  end

  # Detect context type from item structure
  def detect_context_type(item)
    return 'default' unless item.is_a?(Hash)

    # Check for explicit type fields (user-defined)
    return item['type'].to_s if item['type']
    return item['context_type'].to_s if item['context_type']
    return item['model_type'].to_s.downcase if item['model_type']

    # If no explicit type and user has configured contexts, try to match
    context_configs = @options[:context_configs] || {}
    return match_context_by_fields(item, context_configs) if context_configs.any?

    # Default fallback
    'default'
  end

  # Match context type based on configured field patterns
  def match_context_by_fields(item, context_configs)
    item_fields = item.keys.map(&:to_s)
    best_match = find_best_field_match(item_fields, context_configs)
    best_match || 'default'
  end

  # Find the best matching context configuration
  def find_best_field_match(item_fields, context_configs)
    best_match = nil
    best_score = 0

    context_configs.each do |context_type, config|
      next unless config[:fields]&.any?

      score = calculate_field_match_score(item_fields, config[:fields])
      next unless score >= 0.5 && score > best_score

      best_match = context_type
      best_score = score
    end

    best_match
  end

  # Calculate field matching score
  def calculate_field_match_score(item_fields, config_fields)
    return 0 if config_fields.empty?

    matching_fields = (item_fields & config_fields).size
    matching_fields.to_f / config_fields.size
  end

  # Fallback formatting for hash items
  def fallback_format_hash(item, format_data = nil)
    # Fallback: join key-value pairs
    (format_data || item).map { |k, v| "#{k}: #{v}" }.join(', ')
  end
end
