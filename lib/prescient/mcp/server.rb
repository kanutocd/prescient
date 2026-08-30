# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren, Layout/IndentationWidth
module Prescient::MCP
    # Dependency-free MCP capability adapter over Prescient's public API.
    class Server
      # rubocop:disable Layout/HashAlignment
      TOOL_DEFINITIONS = {
        "prescient_generate" => {
          description:  "Generate a text response.",
          input_schema: { type: "object", required: ["prompt"] }
        },
        "prescient_embed" => {
          description:  "Generate an embedding.",
          input_schema: { type: "object", required: ["input"] }
        },
        "prescient_providers" => {
          description:  "List configured providers.",
          input_schema: { type: "object" }
        },
        "prescient_health" => {
          description:  "Check configured provider health.",
          input_schema: { type: "object" }
        },
        "prescient_agent" => {
          description:  "Run a bounded agent task with explicitly supplied tools.",
          input_schema: { type: "object", required: ["prompt"] }
        }
      }.freeze
      # rubocop:enable Layout/HashAlignment

      def initialize(configuration: Configuration.new, client_factory: nil, authorization: nil)
        @configuration = configuration
        @client_factory = client_factory || ->(provider) { Prescient.client(provider) }
        @authorization = authorization
      end

      # Return the MCP initialization response.
      # @return [Hash] Server capabilities and metadata
      def initialize_result
        # rubocop:disable Layout/HashAlignment
        {
          protocolVersion: "2025-06-18",
          serverInfo:   { name: @configuration.name, version: @configuration.version },
          capabilities: { tools: {}, resources: {} }
        }
        # rubocop:enable Layout/HashAlignment
      end

      # Return enabled MCP tool definitions.
      # @return [Array<Hash>] Discoverable tools
      def tools
        @configuration.tools.filter_map do |name|
          definition = TOOL_DEFINITIONS[name]
          definition && { name:, **definition }
        end
      end

      # Return enabled MCP resources.
      # @return [Array<Hash>] Discoverable resources
      def resources
        @configuration.resources.filter_map do |uri|
          next unless Configuration::SUPPORTED_RESOURCES.include?(uri)

          { uri:, name: uri.delete_prefix("prescient://"), mimeType: "application/json" }
        end
      end

      # Execute one enabled MCP tool.
      # @param name [String, Symbol] Tool name
      # @param arguments [Hash] Tool arguments
      # @param context [Hash] Request-scoped context
      # @return [Hash] MCP tool result
      def call_tool(name, arguments = {}, context: {})
        ensure_enabled!(name)
        validate_input(arguments)
        authorize!(name, arguments, context)
        result = case name.to_s
                 when "prescient_generate" then generate(arguments)
                 when "prescient_embed" then embed(arguments)
                 when "prescient_providers" then providers
                 when "prescient_health" then health(arguments)
                 when "prescient_agent" then agent(arguments, context)
                 else raise ArgumentError, "MCP tool not enabled: #{name}"
                 end
        { content: [{ type: "text", text: JSON.generate(result) }], isError: false }
      rescue StandardError => e
        { content: [{ type: "text", text: JSON.generate(error: safe_error(e)) }], isError: true }
      end

      # Read one enabled MCP resource.
      # @param uri [String, Symbol] Resource URI
      # @return [Hash] MCP resource response
      def read_resource(uri)
        payload = case uri.to_s
                  when "prescient://providers" then providers
                  when "prescient://health" then health({})
                  else raise ArgumentError, "MCP resource not enabled: #{uri}"
                  end
        { contents: [{ uri:, mimeType: "application/json", text: JSON.generate(payload) }] }
      end

      private

      def generate(arguments)
        prompt = required_string(arguments, "prompt")
        client_for(arguments).generate_response(prompt, arguments.fetch("context", []), **model_options(arguments))
      end

      def embed(arguments)
        input = required_string(arguments, "input")
        embedding = client_for(arguments).generate_embedding(input, **model_options(arguments))
        { embedding:, dimensions: embedding.length }
      end

      def providers
        { providers: Prescient.configuration.providers.map do |name, registration|
          { name: name.to_s, class: registration[:class].name }
        end }
      end

      def health(arguments)
        provider = arguments["provider"]
        return Prescient.health_check(provider: provider.to_sym) if provider

        Prescient.configuration.providers.keys.to_h { |name| [name.to_s, Prescient.health_check(provider: name)] }
      end

      def agent(arguments, context)
        require "prescient/agent"
        configuration = Prescient::Agent::Configuration.new(max_loops: arguments.fetch("max_loops", 5))
        result = Prescient::Agent::Runtime.new(
          client: client_for(arguments),
          tool_names: arguments.fetch("tools", []),
          configuration: configuration,
          authorization: @authorization,
          request_context: context,
          generation_options: model_options(arguments)
        ).run(required_string(arguments, "prompt"))
        result.to_h
      end

      def client_for(arguments)
        @client_factory.call(arguments["provider"]&.to_sym)
      end

      def model_options(arguments)
        arguments["model"] ? { model: arguments["model"] } : {}
      end

      def required_string(arguments, key)
        value = arguments[key]
        raise ArgumentError, "#{key} must be a non-empty string" unless value.is_a?(String) && !value.empty?

        value
      end

      def validate_input(arguments)
        raise ArgumentError, "MCP arguments must be an object" unless arguments.is_a?(Hash)
        return unless JSON.generate(arguments).bytesize > @configuration.max_input_bytes

        raise ArgumentError, "MCP arguments exceed configured limit"
      end

      def ensure_enabled!(name)
        return if @configuration.tools.include?(name.to_s)

        raise ArgumentError, "MCP tool not enabled: #{name}"
      end

      def authorize!(name, arguments, context)
        return unless @authorization
        return if @authorization.call(tool: name.to_sym, arguments: arguments.dup, context: context.dup) == true

        raise Prescient::AuthenticationError, "MCP authorization denied"
      end

      def safe_error(error)
        return { type: "invalid_request", message: error.message } if error.is_a?(ArgumentError)

        { type: "internal_error", message: "MCP operation failed" }
      end
    end
end
# rubocop:enable Style/ClassAndModuleChildren, Layout/IndentationWidth
