# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Explicit allowlist and invocation boundary for agent tools.
  class ToolRegistry
    # @return [Class] Internal immutable tool descriptor
    Tool = Struct.new(:name, :description, :callable, keyword_init: true)

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

      tool.callable.call(arguments)
    end

    private

    def build_tool(name, tool)
      raise ConfigurationError, "agent tool does not support search: #{name}" unless tool.respond_to?(:search)

      Tool.new(
        name:        name.to_sym,
        description: 'Search using the configured external capability.',
        callable:    ->(arguments) { invoke_search(tool, arguments) },
      )
    end

    def invoke_search(tool, arguments)
      query = arguments['query'] || arguments[:query]
      valid_query = query.is_a?(String) && !query.strip.empty?
      raise MalformedActionError, 'search tool requires a non-empty query' unless valid_query

      tool.search(query, limit: arguments['limit'] || arguments[:limit])
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
