# frozen_string_literal: true

require "openssl"

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::MCP
  # Standard bearer-token authentication policy for HTTP MCP transports.
  module Authentication
    # Authenticates requests with a configured bearer token.
    class BearerToken
      def initialize(token:, principal: nil)
        raise ArgumentError, "token must be a non-empty string" unless token.is_a?(String) && !token.empty?

        @token = token
        @principal = principal
      end

      # Authenticate a Rack environment without exposing the token.
      # @param env [Hash] Rack environment
      # @return [Object, false] Principal on success or false on failure
      def call(env)
        value = env["HTTP_AUTHORIZATION"].to_s
        scheme, candidate = value.split(" ", 2)
        return false unless scheme&.casecmp("Bearer")&.zero? && secure_equal?(candidate.to_s, @token)

        @principal || { type: "bearer" }
      end

      private

      def secure_equal?(candidate, expected)
        return false unless candidate.bytesize == expected.bytesize

        OpenSSL.fixed_length_secure_compare(candidate, expected)
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
