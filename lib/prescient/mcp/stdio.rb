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
          @output.puts(JSON.generate(error_response(nil, -32_700, 'invalid JSON')))
        end
      end

      private

      def handle(request)
        id = request['id']
        result = case request['method']
                 when 'initialize' then @server.initialize_result
                 when 'tools/list' then { tools: @server.tools }
                 when 'tools/call'
                   @server.call_tool(request.dig('params', 'name'), request.dig('params', 'arguments') || {})
                 when 'resources/list' then { resources: @server.resources }
                 when 'resources/read' then @server.read_resource(request.dig('params', 'uri'))
                 else return error_response(id, -32_601, 'method not found')
                 end
        { jsonrpc: '2.0', id:, result: }
      rescue StandardError => e
        error_response(id, -32_600, e.message)
      end

      def error_response(id, code, message)
        { jsonrpc: '2.0', id:, error: { code:, message: } }
      end
    end
end
# rubocop:enable Style/ClassAndModuleChildren, Layout/IndentationWidth
