# frozen_string_literal: true

require 'json'
require_relative '../lib/prescient'

generate = ARGV.delete('--generate')
if ARGV.include?('--help')
  puts 'Usage: ruby examples/web_search.rb [--generate] [QUERY]'
  puts '  --generate  Feed normalized search results to the configured AI provider'
  puts '  PRESCIENT_PROVIDER  Provider used with --generate (default: configured provider)'
  exit
end

query = ARGV.empty? ? 'Ruby HTTP clients' : ARGV.join(' ')

Prescient.configure do |config|
  config.add_tool(
    :web_search,
    Prescient::Tool::SearXNG,
    url: ENV.fetch('SEARXNG_URL', 'http://localhost:8080'),
  )
end

result = if generate
           Prescient.search_and_generate(
             query,
             provider: ENV['PRESCIENT_PROVIDER']&.to_sym,
             limit:    20,
           )
         else
           Prescient.tool(:web_search).search(query, limit: 20)
         end

puts JSON.pretty_generate(result)
