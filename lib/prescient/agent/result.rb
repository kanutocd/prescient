# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Immutable summary of one agent run.
  class Result
    attr_reader :response, :provider, :model, :loops_run, :metadata

    def initialize(response:, provider:, model:, loops_run:, success: true, metadata: {})
      @response = response
      @provider = provider
      @model = model
      @loops_run = loops_run
      @success = success
      @metadata = metadata
    end

    def success?
      @success
    end

    # Serialize the result into a safe structured response.
    # @return [Hash] Result data
    def to_h
      {
        response: @response,
        provider: @provider,
        model: @model,
        loops_run: @loops_run,
        success: success?,
        metadata: @metadata
      }
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
