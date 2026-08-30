# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren, Layout/IndentationWidth
module Prescient::MCP
    # Minimal newline-delimited JSON-RPC transport for local MCP clients.
    class Stdio
      def initialize(server: Server.new, input: $stdin, output: $stdout)
        @server = server
        @input = input
        @output = output
      end

      # Process newline-delimited JSON-RPC requests until input closes.
      # @return [void]
      def run
        @input.each_line do |line|
          request = JSON.parse(line)
          @output.puts(JSON.generate(handle(request)))
          @output.flush
        rescue JSON::ParserError
          @output.puts(JSON.generate(error_response(nil, -32_700, "invalid JSON")))
        end
      end

      private

      def handle(request)
        id = request["id"]
        result = @server.dispatch(request)
        { jsonrpc: "2.0", id:, result: }
      rescue ArgumentError
        error_response(id, -32_601, "MCP method not found")
      rescue StandardError
        error_response(id, -32_600, "MCP operation failed")
      end

      def error_response(id, code, message)
        { jsonrpc: "2.0", id:, error: { code:, message: } }
      end
    end
end
# rubocop:enable Style/ClassAndModuleChildren, Layout/IndentationWidth
