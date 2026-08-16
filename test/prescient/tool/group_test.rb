# frozen_string_literal: true

require 'test_helper'

class ToolGroupTest < PrescientTest
  class Adapter
    attr_reader :calls

    def initialize(result: nil, error: nil)
      @result = result
      @error = error
      @calls = 0
    end

    def search(_query, **_options)
      @calls += 1
      raise @error if @error

      @result
    end
  end

  def test_returns_first_successful_adapter
    first = Adapter.new(result: { source: 'first' })
    second = Adapter.new(result: { source: 'second' })
    group = Prescient::Tool::Group.new(adapters: [first, second])

    assert_equal({ source: 'first' }, group.search('query', limit: 2))
    assert_equal 1, first.calls
    assert_equal 0, second.calls
  end

  def test_falls_back_for_transient_failures
    first = Adapter.new(error: Prescient::ToolConnectionError.new('offline'))
    second = Adapter.new(result: { source: 'second' })
    group = Prescient::Tool::Group.new(adapters: [first, second])

    assert_equal({ source: 'second' }, group.search('query'))
    assert_equal 1, first.calls
    assert_equal 1, second.calls
  end

  def test_does_not_fallback_for_non_transient_failures
    first = Adapter.new(error: Prescient::AuthenticationError.new('unauthorized'))
    second = Adapter.new(result: { source: 'second' })
    group = Prescient::Tool::Group.new(adapters: [first, second])

    assert_raises(Prescient::AuthenticationError) do
      group.search('query')
    end
    assert_equal 0, second.calls
  end

  def test_raises_last_transient_failure_when_all_adapters_fail
    first = Adapter.new(error: Prescient::ToolConnectionError.new('offline'))
    second = Adapter.new(error: Prescient::RateLimitError.new('limited'))
    group = Prescient::Tool::Group.new(adapters: [first, second])

    error = assert_raises(Prescient::RateLimitError) { group.search('query') }

    assert_equal 'limited', error.message
  end

  def test_rejects_empty_groups
    assert_raises(Prescient::ToolConfigurationError) do
      Prescient::Tool::Group.new(adapters: [])
    end
  end
end
