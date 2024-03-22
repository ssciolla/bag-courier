require "securerandom"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/archivematica"
require_relative "../lib/repository_data"

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

    @mock_backend = Minitest::Mock.new
    @mocked_api = ArchivematicaAPI.new(
      api_backend: @mock_backend
    )

    # Using default api_backend class and api_prefix "/api/v2/"
    @api = ArchivematicaAPI.from_config(
      base_url: base_url,
      username: username,
      api_key: api_key
    )
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

    expected_params = {"current_location" => @location_uuid, "limit" => 1}
    @mock_backend.expect(
      :get,
      first_data,
      ["file/", expected_params]
    )
    @mock_backend.expect(
      :get,
      second_data,
      ["file/?current_location=#{@location_uuid}&limit=1&offset=1", nil]
    )
    @mock_backend.expect(
      :get,
      third_data,
      ["file/?current_location=#{@location_uuid}&limit=1&offset=2", nil]
    )
    objects = @mocked_api.get_objects_from_pages("file/", {
      "current_location" => @location_uuid,
      "limit" => 1
    })
    @mock_backend.verify
    assert_equal objects, @package_data
  end

  def test_get_packages_with_no_stored_date
    args_checker = lambda do |url, params|
      assert_equal "file/", url
      expected_params = {
        "current_location" => @location_uuid,
        "status" => "UPLOADED"
      }
      assert_equal expected_params, params
      @package_data
    end

    @api.stub :get_objects_from_pages, args_checker do
      packages = @api.get_packages(location_uuid: @location_uuid)
      assert packages.all? { |p| p.is_a?(Archivematica::Package) }
      assert_equal(@package_data.map { |p| p["uuid"] }, packages.map { |p| p.uuid })
    end
  end

  def test_get_packages_with_stored_date
    time_filter = Time.utc(2024, 1, 12)

    args_checker = lambda do |url, params|
      assert_equal "file/", url
      expected_params = {
        "current_location" => @location_uuid,
        "status" => "UPLOADED",
        "stored_date__gt" => "2024-01-12T00:00:00.000000"
      }
      assert_equal expected_params, params
      @package_data
    end

    @api.stub :get_objects_from_pages, args_checker do
      packages = @api.get_packages(location_uuid: @location_uuid, stored_date: time_filter)
      assert packages.all? { |p| p.is_a?(Archivematica::Package) }
      assert_equal(@package_data.map { |p| p["uuid"] }, packages.map { |p| p.uuid })
    end
  end
end

class ArchivematicaServiceTest < Minitest::Test
  include Archivematica
  include RepositoryData
  include PackageTestUtils

  def setup
    @mock_api = Minitest::Mock.new
    @location_uuid = SecureRandom.uuid
    @stored_date = Time.utc(2024, 2, 17)

    uuids = Array.new(2) { SecureRandom.uuid }
    @test_packages = [
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
        stored_date: "2024-02-19T00:00:00.000000"
      )
    ]
  end

  def test_get_package_data_objects_with_no_filter
    service = ArchivematicaService.new(
      name: "test",
      api: @mock_api,
      location_uuid: @location_uuid
    )

    @mock_api.expect(:get_packages, @test_packages, location_uuid: @location_uuid, stored_date: @stored_date)
    package_data_objs = service.get_package_data_objects(stored_date: @stored_date)
    @mock_api.verify

    # No objects are filtered out
    first_package, second_package = @test_packages
    expected = [
      RepositoryPackageData.new(
        remote_path: first_package.path,
        metadata: ObjectMetadata.new(
          id: first_package.uuid,
          title: "#{first_package.uuid} / identifier-one",
          creator: "Not available",
          description: "Not available"
        ),
        context: "test",
        stored_time: Time.utc(2024, 2, 18)
      ),
      RepositoryPackageData.new(
        remote_path: second_package.path,
        metadata: ObjectMetadata.new(
          id: second_package.uuid,
          title: "#{second_package.uuid} / identifier-two",
          creator: "Not available",
          description: "Not available"
        ),
        context: "test",
        stored_time: Time.utc(2024, 2, 19)
      )
    ]
    assert_equal expected, package_data_objs
  end

  def test_get_package_data_objects_with_size_filter
    service = ArchivematicaService.new(
      name: "test",
      api: @mock_api,
      location_uuid: @location_uuid
    )

    @mock_api.expect(:get_packages, @test_packages, location_uuid: @location_uuid, stored_date: @stored_date)
    package_data_objs = service.get_package_data_objects(
      stored_date: @stored_date,
      package_filter: SizePackageFilter.new(4000000)
    )
    @mock_api.verify

    # Larger object is filtered out
    assert_equal 1, package_data_objs.length
    assert_equal package_data_objs[0].metadata.id, @test_packages[0].uuid
  end
end
