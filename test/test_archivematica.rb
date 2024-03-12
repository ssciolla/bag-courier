require "securerandom"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/archivematica"
require_relative "../lib/repository_package"

module PackageTestUtils
  def make_path(uuid)
    uuid.delete("-").chars.each_slice(4).map(&:join).join("/")
  end
end

class ArchivematicaAPITest < Minitest::Test
  include Archivematica
  include PackageTestUtils

  def setup
    base_url = "http://archivematica.storage.api.org:8000"
    username = "youruser"
    api_key = "some-secret-key"
    api_prefix = "/api/v2/"

    @location_uuid = SecureRandom.uuid
    @location_url = "#{api_prefix}location/#{@location_uuid}/"
    @request_url_stem = base_url + api_prefix

    uuids = Array.new(3) { SecureRandom.uuid }
    @package_data = [
      {
        "uuid" => uuids[0],
        "current_full_path" => "/storage/#{make_path(uuids[0])}/identifier-one-#{uuids[0]}",
        "size" => 1000,
        "stored_date" => "2024-01-17T00:00:00.000000",
        "status" => "UPLOADED",
        "current_location" => @location_url
      },
      {
        "uuid" => uuids[1],
        "current_full_path" => "/storage/#{make_path(uuids[1])}/identifier-two-#{uuids[1]}",
        "size" => 300000,
        "stored_date" => "2024-01-16T00:00:00.000000",
        "status" => "UPLOADED",
        "current_location" => @location_url
      },
      {
        "uuid" => uuids[2],
        "current_full_path" => "/storage/#{make_path(uuids[2])}/identifier-three-#{uuids[2]}",
        "size" => 5000000,
        "stored_date" => "2024-01-13T00:00:00.000000",
        "status" => "UPLOADED",
        "current_location" => @location_url
      }
    ]

    @stubs = Faraday::Adapter::Test::Stubs.new
    stubbed_test_conn = Faraday.new(
      url: "#{base_url}#{api_prefix}",
      headers: {"Authorization" => "ApiKey #{username}:#{api_key}"}
    ) do |builder|
      builder.request :retry
      builder.response :raise_error

      builder.adapter :test, @stubs
    end

    # Using default api_prefix "/api/v2/"
    @stubbed_api = ArchivematicaAPI.new(stubbed_test_conn)
    @api = ArchivematicaAPI.from_config(
      base_url: base_url,
      username: username,
      api_key: api_key
    )
  end

  def test_get_throws_unauthorized_error_with_response_info
    @stubs.get(@request_url_stem + "file/") do |env|
      [401, {"Content-Type": "text/plain"}, "Unauthorized"]
    end
    error = assert_raises ArchivematicaAPIError do
      @stubbed_api.get("file/")
    end
    expected = "Error occurred while interacting with Archivematica API. " \
      "Error type: Faraday::UnauthorizedError; " \
      "status code: 401; " \
      "body: Unauthorized"
    assert_equal expected, error.message
  end

  def test_get_retries_on_timeout_to_failure
    calls = 0
    @stubs.get(@request_url_stem + "file/") do |env|
      calls += 1
      env[:body] = nil
      raise Faraday::TimeoutError
    end

    # Final error is caught and transformed.
    error = assert_raises ArchivematicaAPIError do
      @stubbed_api.get("file/")
    end
    expected = "Error occurred while interacting with Archivematica API. " \
      "Error type: Faraday::TimeoutError; " \
      "status code: none; " \
      "body: none"
    assert_equal expected, error.message

    assert_equal 3, calls
  end

  def test_get_retries_on_timeout_failing_once_then_succeeding
    calls = 0
    @stubs.get(@request_url_stem + "file/") do |env|
      env[:body] = nil
      calls += 1
      if calls < 2
        raise Faraday::TimeoutError
      else
        [200, {"Content-Type": "application/json"}, "{}"]
      end
    end

    data = @stubbed_api.get("file/")
    assert_equal 2, calls
    assert_equal ({}), data
  end

  def test_get_objects_from_pages
    file_page_url_stem = "#{@api_prefix}file/?current_location=#{@location_uuid}&limit=1"
    first_data = {
      "meta" => {
        "limit" => 1,
        "next" => "#{file_page_url_stem}&offset=1",
        "offset" => 0,
        "previous" => nil,
        "total_count" => 3
      },
      "objects" => [@package_data[0]]
    }
    second_data = {
      "meta" => {
        "limit" => 1,
        "next" => "#{file_page_url_stem}&offset=2",
        "offset" => 1,
        "previous" => "#{file_page_url_stem}&offset=0",
        "total_count" => 3
      },
      "objects" => [@package_data[1]]
    }
    third_data = {
      "meta" => {
        "limit" => 1,
        "next" => nil,
        "offset" => 2,
        "previous" => "#{file_page_url_stem}&offset=2",
        "total_count" => 3
      },
      "objects" => [@package_data[2]]
    }
    stubbed_values = [first_data, second_data, third_data]
    @api.stub :get, proc { stubbed_values.shift } do
      objects = @api.get_objects_from_pages("file/", {
        "current_location" => @location_uuid
      })
      assert_equal objects, @package_data
    end
  end

  def test_get_packages_with_no_stored_date
    @api.stub :get_objects_from_pages, @package_data do
      packages = @api.get_packages(location_uuid: @location_uuid)
      assert packages.all? { |p| p.is_a?(Archivematica::Package) }
      assert_equal(@package_data.map { |p| p["uuid"] }, packages.map { |p| p.uuid })
    end
  end

  def test_get_packages_with_stored_date
    time_filter = Time.utc(2024, 1, 12).iso8601
    @api.stub :get_objects_from_pages, @package_data do
      packages = @api.get_packages(location_uuid: @location_uuid, stored_date: time_filter)
      assert packages.all? { |p| p.is_a?(Archivematica::Package) }
      assert_equal(@package_data.map { |p| p["uuid"] }, packages.map { |p| p.uuid })
    end
  end

  def teardown
    Faraday.default_connection = nil
  end
end

class ArchivematicaServiceTest < Minitest::Test
  include Archivematica
  include RepositoryPackage
  include PackageTestUtils

  def setup
    @mock_api = Minitest::Mock.new
    @location_uuid = SecureRandom.uuid
    @stored_date = Time.utc(2024, 2, 17).iso8601
    @object_size_limit = 4000000
  end

  def test_get_repository_packages
    service = ArchivematicaService.new(
      name: "test",
      api: @mock_api,
      location_uuid: @location_uuid,
      stored_date: @stored_date,
      object_size_limit: @object_size_limit
    )

    uuids = Array.new(2) { SecureRandom.uuid }
    test_packages = [
      Package.new(
        uuid: uuids[0],
        path: "/storage/#{make_path(uuids[0])}/identifier-one-#{uuids[0]}",
        size: 200000,
        stored_date: "2024-02-18T00:00:00.000000"
      ),
      Package.new(
        uuid: uuids[1],
        path: "/storage/#{make_path(uuids[1])}/identifier-two-#{uuids[1]}",
        size: 500000000,
        stored_date: "2024-02-18T00:00:00.000000"
      )
    ]

    @mock_api.expect(:get_packages, test_packages, location_uuid: @location_uuid, stored_date: @stored_date)
    repository_packages = service.get_repository_packages
    @mock_api.verify

    # filters out larger bag
    assert_equal 1, repository_packages.length

    first_package = test_packages[0]
    expected = RepositoryPackage.new(
      remote_path: first_package.path,
      metadata: ObjectMetadata.new(
        id: first_package.uuid,
        title: "#{first_package.uuid} / identifier-one",
        creator: "Not available",
        description: "Not available"
      ),
      context: "test",
      stored_time: Time.utc(2024, 2, 18)
    )
    assert_equal expected, repository_packages[0]
  end
end
