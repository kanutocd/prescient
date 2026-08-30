# frozen_string_literal: true

require 'json'

# Optional bounded agent orchestration over Prescient Core.
module Prescient::Agent
end

require_relative 'agent/configuration'
require_relative 'agent/errors'
require_relative 'agent/error_serializer'
require_relative 'agent/result'
require_relative 'agent/context'
require_relative 'agent/parser'
require_relative 'agent/prompt_builder'
require_relative 'agent/tool_registry'
require_relative 'agent/runtime'
