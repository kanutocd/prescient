# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Extracts and validates one tool action from provider text.
  class Parser
    # @return [String] Opening fenced JSON marker
    JSON_FENCE = "```json".b.freeze
    # @return [String] Closing fenced JSON marker
    CLOSING_FENCE = "```".b.freeze
    # @return [Array<Integer>] JSON whitespace byte values
    WHITESPACE_BYTES = [9, 10, 11, 12, 13, 32].freeze

    # Parse one optional action from provider output.
    # @param text [String] Provider response text
    # @param max_bytes [Integer] Maximum action size
    # @return [Hash, nil] Parsed action or nil for a final response
    def self.parse(text, max_bytes: Configuration::DEFAULT_MAX_ACTION_BYTES)
      new(max_bytes:).parse(text)
    end

    def initialize(max_bytes: Configuration::DEFAULT_MAX_ACTION_BYTES)
      @max_bytes = max_bytes
    end

    # Parse one optional action from provider output.
    # @param text [String] Provider response text
    # @return [Hash, nil] Parsed action or nil for a final response
    def parse(text)
      action_json = extract_action_json(text.to_s)
      return nil unless action_json
      raise MalformedActionError, "agent action exceeds configured size limit" if action_json.bytesize > @max_bytes

      payload = JSON.parse(action_json)
      validate_payload(payload)
      { name: payload.fetch("action").to_sym, arguments: payload.fetch("args") }
    rescue JSON::ParserError => e
      raise MalformedActionError, "agent action contains invalid JSON: #{e.message}"
    end

    private

    def extract_action_json(text)
      source = text.b
      cursor = 0

      while (fence_start = source.index(JSON_FENCE, cursor))
        content_start = skip_whitespace(source, fence_start + JSON_FENCE.bytesize)
        unless source.getbyte(content_start) == 123
          cursor = content_start
          next
        end

        action_json, next_cursor = scan_json_object(source, content_start)
        return action_json if action_json

        cursor = next_cursor
      end

      nil
    end

    def scan_json_object(source, start)
      depth = 0
      escaped = false
      in_string = false
      index = start

      while index < source.bytesize
        byte = source.getbyte(index)
        if in_string
          in_string, escaped = string_state(byte, escaped)
        elsif fence_at?(source, index)
          return [nil, index]
        else
          in_string = byte == 34
          depth = depth_after(byte, depth)
          return completed_action(source, start, index) if byte == 125 && depth.zero?
        end
        index += 1
      end

      [nil, source.bytesize]
    end

    def string_state(byte, escaped)
      return [true, false] if escaped
      return [true, true] if byte == 92
      return [false, false] if byte == 34

      [true, false]
    end

    def fence_at?(source, index)
      byte = source.getbyte(index)
      byte == 96 && source.byteslice(index, JSON_FENCE.bytesize) == JSON_FENCE
    end

    def depth_after(byte, depth)
      case byte
      when 123 then depth + 1
      when 125 then depth - 1
      else depth
      end
    end

    def completed_action(source, start, index)
      closing_start = skip_whitespace(source, index + 1)
      return [nil, closing_start] unless source.byteslice(closing_start, CLOSING_FENCE.bytesize) == CLOSING_FENCE

      length = index + 1 - start
      [source.byteslice(start, length).force_encoding(Encoding::UTF_8), index + 1]
    end

    def skip_whitespace(source, start)
      index = start
      index += 1 while index < source.bytesize && WHITESPACE_BYTES.include?(source.getbyte(index))
      index
    end

    def validate_payload(payload)
      unless payload.is_a?(Hash) && payload.keys.sort == %w[action args]
        raise MalformedActionError, "agent action must contain only action and args"
      end
      return if payload["action"].is_a?(String) && !payload["action"].empty? && payload["args"].is_a?(Hash)

      raise MalformedActionError, "agent action must define a name and object args"
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
