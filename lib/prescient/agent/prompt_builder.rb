# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Builds deterministic instructions for the single-action agent protocol.
  class PromptBuilder
    # Build the system instruction for one agent run.
    # @param system_instruction [String] Application-specific instruction
    # @param tools [Array<ToolRegistry::Tool>] Allowed tools
    # @return [String] Deterministic orchestration prompt
    def self.build(system_instruction:, tools:)
      tool_text = tools.empty? ? "None" : tools.map { |tool| tool_instruction(tool) }.join("\n")
      <<~PROMPT
        #{system_instruction}

        You may either answer the task directly or request exactly one tool.
        For a tool request, return one JSON object in a fenced json block:
        {"action":"tool_name","args":{"key":"value"}}
        Available tools:
        #{tool_text}
        Never request an unavailable tool. Do not return more than one action.
      PROMPT
    end

    def self.tool_instruction(tool)
      "- #{tool.name}: #{tool.description} (arguments: #{JSON.generate(tool.schema)})"
    end
    private_class_method :tool_instruction
  end
end
# rubocop:enable Style/ClassAndModuleChildren
