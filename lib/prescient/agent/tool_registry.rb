# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Explicit allowlist and invocation boundary for agent tools.
  class ToolRegistry
    # @return [Class] Internal immutable tool descriptor
    Tool = Struct.new(:name, :description, :schema, :callable, keyword_init: true)

    def initialize(tools)
      @tools = tools.to_h { |name, tool| [name.to_sym, build_tool(name, tool)] }
    end

    # Return all explicitly allowed tools.
    # @return [Array<Tool>] Tool descriptors
    def all
      @tools.values
    end

    def invoke(name, arguments)
      tool = @tools[name.to_sym]
      raise UnauthorizedToolError, "agent tool not allowed: #{name}" unless tool

      SchemaValidator.validate!(tool.schema, arguments)
      tool.callable.call(arguments)
    end

    private

    def build_tool(name, tool)
      unless tool.respond_to?(:search) || tool.respond_to?(:call)
        raise ConfigurationError, "agent tool does not support invocation: #{name}"
      end

      Tool.new(
        name: name.to_sym,
        description: tool_description(tool),
        schema: tool_schema(tool),
        callable: ->(arguments) { invoke_tool(tool, arguments) }
      )
    end

    def invoke_tool(tool, arguments)
      return tool.call(arguments) if tool.respond_to?(:call)

      invoke_search(tool, arguments)
    end

    def invoke_search(tool, arguments)
      query = arguments["query"] || arguments[:query]
      valid_query = query.is_a?(String) && !query.strip.empty?
      raise MalformedActionError, "search tool requires a non-empty query" unless valid_query

      tool.search(query, limit: arguments["limit"] || arguments[:limit])
    end

    def tool_description(tool)
      return tool.description if tool.respond_to?(:description)

      return "Search using the configured external capability." if tool.respond_to?(:search)

      "Invoke the configured external capability."
    end

    def tool_schema(tool)
      return tool.schema if tool.respond_to?(:schema)

      tool.respond_to?(:search) ? { type: "object", required: ["query"] } : { type: "object" }
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
