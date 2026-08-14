# frozen_string_literal: true

require 'json'
require_relative '../lib/prescient'

query = ARGV.empty? ? 'Ruby HTTP clients' : ARGV.join(' ')

Prescient.configure do |config|
  config.add_tool(
    :web_search,
    Prescient::Tool::SearXNG,
    url: ENV.fetch('SEARXNG_URL', 'http://localhost:8080'),
  )
end

puts JSON.pretty_generate(Prescient.tool(:web_search).search(query))
