# frozen_string_literal: true

require 'json'
require_relative '../lib/prescient'

api = Prescient::API.new(
  authentication: ->(env) {
    expected = ENV.fetch('PRESCIENT_API_TOKEN', nil)
    expected && env['HTTP_AUTHORIZATION'] == "Bearer #{expected}"
  },
)

endpoints = Prescient::API::ROUTES.keys.map { |method, path|
  { method: method, path: path }
}

app = ->(env) {
  if env['REQUEST_METHOD'] == 'GET' && env['PATH_INFO'] == '/'
    payload = JSON.generate({ name: 'Prescient API', endpoints: endpoints })
    [200, { 'content-type' => 'application/json', 'content-length' => payload.bytesize.to_s }, [payload]]
  else
    api.call(env)
  end
}

if respond_to?(:run, true)
  run app
else
  puts JSON.pretty_generate({ name: 'Prescient API', endpoints: endpoints })
end
