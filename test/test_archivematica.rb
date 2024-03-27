require "securerandom"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/archivematica"
require_relative "../lib/repository_data"

class ArchivematicaAPITest < Minitest::Test
  include Archivematica

  def setup
    base_url = "http://archivematica.storage.api.org:8000"
    username = "youruser"
    api_key = "some-secret-key"
    api_prefix = "/api/v2/"

    @location_uuid = "379f096b-5386-4259-a7bd-adb0dfbe8390"
    @location_url = "/api/v2/location/379f096b-5386-4259-a7bd-adb0dfbe8390/"
    @request_url_stem = base_url + api_prefix

    @package_data = [
      {
        "uuid" => "9e7bbf35-9e31-4679-9228-e132ddcf34ea",
        "current_full_path" => "/storage/9e7b/bf35/9e31/4679/9228/e132/ddcf/34ea/identifier-one-9e7bbf35-9e31-4679-9228-e132ddcf34ea",
        "size" => 1000,
        "stored_date" => "2024-01-17T00:00:00.000000",
        "status" => "UPLOADED",
        "current_location" => @location_url
      },
      {
        "uuid" => "590a9015-a5ef-47af-b0da-276a88ecd543",
        "current_full_path" => "/storage/590a/9015/a5ef/47af/b0da/276a/88ec/d543/identifier-two-590a9015-a5ef-47af-b0da-276a88ecd543",
        "size" => 300000,
        "stored_date" => "2024-01-16T00:00:00.000000",
        "status" => "UPLOADED",
        "current_location" => @location_url
      },
      {
        "uuid" => "4fb38e65-a972-434e-a32c-d668a122514a",
        "current_full_path" => "/storage/4fb3/8e65/a972/434e/a32c/d668/a122/514a/identifier-three-4fb38e65-a972-434e-a32c-d668a122514a",
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
      url: "file/",
      params: expected_params
    )
    @mock_backend.expect(
      :get,
      second_data,
      url: "file/?current_location=#{@location_uuid}&limit=1&offset=1",
      params: nil
    )
    @mock_backend.expect(
      :get,
      third_data,
      url: "file/?current_location=#{@location_uuid}&limit=1&offset=2",
      params: nil
    )
    objects = @mocked_api.get_objects_from_pages(url: "file/", params: {
      "current_location" => @location_uuid,
      "limit" => 1
    })
    @mock_backend.verify
    assert_equal objects, @package_data
  end

  def test_get_packages_with_no_stored_date
    args_checker = lambda do |kwargs|
      assert_equal "file/", kwargs[:url]
      expected_params = {
        "current_location" => @location_uuid,
        "status" => "UPLOADED"
      }
      assert_equal expected_params, kwargs[:params]
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

    args_checker = lambda do |kwargs|
      assert_equal "file/", kwargs[:url]
      expected_params = {
        "current_location" => @location_uuid,
        "status" => "UPLOADED",
        "stored_date__gt" => "2024-01-12T00:00:00.000000"
      }
      assert_equal expected_params, kwargs[:params]
      @package_data
    end

    @api.stub :get_objects_from_pages, args_checker do
      packages = @api.get_packages(location_uuid: @location_uuid, stored_date: time_filter)
      assert packages.all? { |p| p.is_a?(Archivematica::Package) }
      assert_equal(@package_data.map { |p| p["uuid"] }, packages.map { |p| p.uuid })
    end
  end

  def test_get_package_when_exists
    first_package_data = @package_data[0]

    expected = Package.new(
      uuid: "9e7bbf35-9e31-4679-9228-e132ddcf34ea",
      path: "/storage/9e7b/bf35/9e31/4679/9228/e132/ddcf/34ea/identifier-one-9e7bbf35-9e31-4679-9228-e132ddcf34ea",
      size: 1000,
      stored_date: "2024-01-17T00:00:00.000000"
    )

    @mock_backend.expect(:get, first_package_data, url: "file/#{first_package_data["uuid"]}")
    package = @mocked_api.get_package(first_package_data["uuid"])
    @mock_backend.verify
    assert_equal expected, package
  end

  def test_get_package_when_does_not_exist
    uuid = SecureRandom.uuid
    @mock_backend.expect(:get, nil, url: "file/#{uuid}")
    package = @mocked_api.get_package(uuid)
    @mock_backend.verify
    assert_nil package
  end
end

class ArchivematicaServiceTest < Minitest::Test
  include Archivematica
  include RepositoryData

  def setup
    @mock_api = Minitest::Mock.new
    @location_uuid = SecureRandom.uuid
    @stored_date = Time.utc(2024, 2, 17)

    @test_packages = [
      Package.new(
        uuid: "0948e2ae-eb24-4984-a71b-43bc440534d0",
        path: "/storage/0948/e2ae/eb24/4984/a71b/43bc/4405/34d0/identifier-one-0948e2ae-eb24-4984-a71b-43bc440534d0",
        size: 200000,
        stored_date: "2024-02-18T00:00:00.000000"
      ),
      Package.new(
        uuid: "0baa468e-dd42-49ff-ba90-5dedc30c8541",
        path: "/storage/0baa/468e/dd42/49ff/ba90/5ded/c30c/8541/identifier-two-0baa468e-dd42-49ff-ba90-5dedc30c8541",
        size: 500000000,
        stored_date: "2024-02-19T00:00:00.000000"
      )
    ]

    @service = ArchivematicaService.new(
      name: "test",
      api: @mock_api,
      location_uuid: @location_uuid
    )
  end

  def test_get_package_data_objects_with_no_filter
    @mock_api.expect(:get_packages, @test_packages, location_uuid: @location_uuid, stored_date: @stored_date)
    package_data_objs = @service.get_package_data_objects(stored_date: @stored_date)
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
        stored_time: Time.utc(2024, 2, 19)
      )
    ]
    assert_equal expected, package_data_objs
  end

  def test_get_package_data_objects_with_size_filter
    @mock_api.expect(:get_packages, @test_packages, location_uuid: @location_uuid, stored_date: @stored_date)
    package_data_objs = @service.get_package_data_objects(
      stored_date: @stored_date,
      package_filter: SizePackageFilter.new(4000000)
    )
    @mock_api.verify

    # Larger object is filtered out
    assert_equal 1, package_data_objs.length
    assert_equal package_data_objs[0].metadata.id, @test_packages[0].uuid
  end

  def test_get_package_data_object
    first_package = @test_packages[0]
    @mock_api.expect(:get_package, first_package, [first_package.uuid])
    package_data_obj = @service.get_package_data_object(first_package.uuid)
    assert package_data_obj.is_a?(RepositoryPackageData)
    assert_equal first_package.path, package_data_obj.remote_path
  end
end
