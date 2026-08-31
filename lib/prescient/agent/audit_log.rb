# frozen_string_literal: true

require "json"
require "monitor"
require "time"

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Persists safe Agent telemetry events as newline-delimited JSON.
  class AuditLog
    # Telemetry keys permitted in durable audit records.
    # @return [Array<Symbol>] Safe event fields
    FIELDS = %i[event loop loops_run actions success phase error].freeze

    # @param path [String, nil] File path opened in append mode
    # @param io [#write, nil] Writable stream owned by the caller
    def initialize(path: nil, io: nil)
      raise ArgumentError, "provide path or io, not both" if path && io
      raise ArgumentError, "path or io is required" unless path || io

      @io = io || File.open(path, "a")
      @lock = Monitor.new
    end

    # Persist one allowlisted telemetry event.
    # @param event [Hash] Agent event metadata
    # @return [void]
    def call(event)
      record = event.slice(*FIELDS).merge(timestamp: Time.now.utc.iso8601)
      @lock.synchronize do
        @io.write("#{JSON.generate(record)}\n")
        @io.flush if @io.respond_to?(:flush)
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
