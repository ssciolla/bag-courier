require "faraday"
require "faraday/retry"
require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/api_backend"

class FaradayAPIBackendTest < Minitest::Test
  include APIBackend

  def setup
    @base_url = "http://some-service.org/api/v1/"
    @headers = {"Authorization" => "ApiKey youruser:some-secret-key"}
    @stubs = Faraday::Adapter::Test::Stubs.new
    @stubbed_api_backend = FaradayAPIBackend.new(
      base_url: @base_url, headers: @headers
    ) do |builder|
      builder.adapter :test, @stubs
    end
  end

  def test_new_works_without_block
    backend = FaradayAPIBackend.new(base_url: @base_url, headers: @headers)
    assert backend.is_a?(FaradayAPIBackend)
    assert backend.respond_to?(:get)
  end

  def test_get_throws_unauthorized_error_with_response_info
    @stubs.get(@base_url + "file/") do |env|
      [401, {"Content-Type": "text/plain"}, "Unauthorized"]
    end
    error = assert_raises APIError do
      @stubbed_api_backend.get(url: "file/")
    end
    expected = "Error occurred while interacting with REST API at #{@base_url}. " \
      "Error type: Faraday::UnauthorizedError; " \
      "status code: 401; " \
      "body: Unauthorized"
    assert_equal expected, error.message
  end

  def test_get_returns_nil_when_resource_not_found
    @stubs.get(@base_url + "file/") do |env|
      [404, {"Content-Type": "text/plain"}, "Resource not found"]
    end
    result = @stubbed_api_backend.get(url: "file/")
    refute(result)
  end

  def test_get_retries_on_timeout_to_failure
    calls = 0
    @stubs.get(@base_url + "file/") do |env|
      calls += 1
      env[:body] = nil
      raise Faraday::TimeoutError
    end

    # Final error is caught and transformed.
    error = assert_raises APIError do
      @stubbed_api_backend.get(url: "file/")
    end
    expected = "Error occurred while interacting with REST API at http://some-service.org/api/v1/. " \
      "Error type: Faraday::TimeoutError; " \
      "status code: none; " \
      "body: none"
    assert_equal expected, error.message

    assert_equal 3, calls
  end

  def test_get_retries_on_timeout_failing_once_then_succeeding
    calls = 0
    @stubs.get(@base_url + "file/") do |env|
      env[:body] = nil
      calls += 1
      if calls < 2
        raise Faraday::TimeoutError
      else
        [200, {"Content-Type": "application/json"}, "{}"]
      end
    end

    data = @stubbed_api_backend.get(url: "file/")
    assert_equal 2, calls
    assert_equal ({}), data
  end

  def teardown
    Faraday.default_connection = nil
  end
end
