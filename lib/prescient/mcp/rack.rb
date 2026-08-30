# frozen_string_literal: true

require "json"
require "securerandom"
require "stringio"

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::MCP
  # Optional Rack-compatible MCP HTTP handler with explicit authentication.
  class Rack
    def initialize(authentication:, server: Server.new, request_context: nil,
                   max_body_bytes: Configuration::DEFAULT_MAX_INPUT_BYTES)
      @server = server
      @authentication = authentication
      @request_context = request_context
      @max_body_bytes = validate_limit(max_body_bytes)
    end

    # Handle one MCP JSON-RPC HTTP request.
    # @param env [Hash] Rack environment
    # @return [Array] Rack response
    def call(env)
      return response(404, { error: "not_found" }) unless env["REQUEST_METHOD"] == "POST"
      return response(401, { error: "authentication_required" }) unless authenticated?(env)

      request = parse_request(env)
      result = @server.dispatch(request, context: request_context(env))
      response(200, { jsonrpc: "2.0", id: request["id"], result: })
    rescue JSON::ParserError
      response(400, { error: "invalid_json" })
    rescue ArgumentError
      response(400, { error: "invalid_request" })
    rescue StandardError
      response(500, { error: "internal_error" })
    end

    private

    def authenticated?(env)
      result = @authentication.call(env)
      result != false && !result.nil?
    end

    def parse_request(env)
      body = env.fetch("rack.input", StringIO.new).read(@max_body_bytes + 1)
      raise ArgumentError, "request body exceeds configured limit" if body.bytesize > @max_body_bytes

      request = JSON.parse(body)
      raise ArgumentError, "request must be an object" unless request.is_a?(Hash)

      request
    end

    def request_context(env)
      base = {
        request_id: SecureRandom.uuid,
        tenant_id: env["HTTP_X_TENANT_ID"],
        principal: env["REMOTE_USER"]
      }.compact
      return base unless @request_context

      context = @request_context.call(env)
      raise ArgumentError, "request context hook must return a mapping" unless context.is_a?(Hash)

      base.merge(context)
    end

    def response(status, payload)
      body = JSON.generate(payload)
      [status, { "content-type" => "application/json", "content-length" => body.bytesize.to_s }, [body]]
    end

    def validate_limit(value)
      return value if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "max_body_bytes must be a positive integer"
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
