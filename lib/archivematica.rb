require "semantic_logger"

require_relative "api_backend"
require_relative "repository_data"

module Archivematica
  Package = Struct.new(
    "Package",
    :uuid,
    :path,
    :size,
    :stored_date,
    keyword_init: true
  )

  module PackageStatus
    UPLOADED = "UPLOADED"
    DELETED = "DELETED"
  end

  class ArchivematicaAPI
    include SemanticLogger::Loggable

    LOCATION_PATH = "location/"
    PACKAGE_PATH = "file/"
    API_V2 = "/api/v2/"

    def initialize(api_backend:, api_prefix: API_V2)
      @backend = api_backend
      @api_prefix = api_prefix
    end

    def self.from_config(
      base_url:,
      username:,
      api_key:,
      api_backend: APIBackend::FaradayAPIBackend,
      api_prefix: API_V2
    )
      backend = api_backend.new(
        base_url: "#{base_url}#{api_prefix}",
        headers: {"Authorization" => "ApiKey #{username}:#{api_key}"}
      )
      new(api_backend: backend, api_prefix: api_prefix)
    end

    def get_next_url(meta)
      (meta.key?("next") && meta["next"].is_a?(String)) ?
        meta["next"].gsub(@api_prefix, "") : nil
    end
    private :get_next_url

    def get_objects_from_pages(url:, params: nil)
      no_more_pages = false
      current_url = url
      current_params = params
      results = []
      logger.debug("Starting URL: #{current_url}")
      until no_more_pages
        data = @backend.get(url: current_url, params: current_params)
        results += data["objects"]
        meta = data["meta"]
        logger.debug("Meta: #{meta}")
        next_url = get_next_url(meta)
        if next_url.nil?
          no_more_pages = true
        else
          current_url = next_url
          current_params = nil
        end
      end
      results
    end

    def create_package(package_data)
      Package.new(
        uuid: package_data["uuid"],
        path: package_data["current_full_path"],
        size: package_data["size"],
        stored_date: package_data["stored_date"]
      )
    end
    private :create_package

    # Returns package or nil if it doesn't exist
    def get_package(uuid)
      package_data = @backend.get(url: PACKAGE_PATH + uuid)
      package_data && create_package(package_data)
    end

    def get_packages(location_uuid:, stored_date: nil)
      params = {
        "current_location" => location_uuid,
        "status" => PackageStatus::UPLOADED
      }
      formatted_stored_date = nil
      if stored_date
        formatted_stored_date = stored_date.strftime("%Y-%m-%dT%H:%M:%S.%6N")
        params["stored_date__gt"] = formatted_stored_date
      end

      package_objects = get_objects_from_pages(url: PACKAGE_PATH, params: params)
      packages = package_objects.map { |o| create_package(o) }
      logger.info(
        "Number of packages found in location #{location_uuid} " +
        "with #{PackageStatus::UPLOADED} status" +
        (formatted_stored_date ? " and with stored date after #{formatted_stored_date}" : "") +
        ": #{packages.length}"
      )
      packages
    end
  end

  class PackageFilterBase
    def filter(packages)
      raise NotImplementedError
    end
  end

  class AllPackageFilter < PackageFilterBase
    def filter(packages)
      packages
    end
  end

  class SizePackageFilter < PackageFilterBase
    include SemanticLogger::Loggable

    def initialize(size_limit)
      @size_limit = size_limit
    end

    def filter(packages)
      filtered_packages = packages.filter { |p| p.size < @size_limit }
      logger.info("Number of packages below object size limit of #{@size_limit}: #{filtered_packages.length}")
      filtered_packages
    end
  end

  class ArchivematicaService
    include SemanticLogger::Loggable

    NA = "Not available"

    attr_reader :name

    def initialize(name:, api:, location_uuid:)
      @name = name
      @api = api
      @location_uuid = location_uuid
    end

    def create_package_data_object(package)
      logger.debug(package)
      inner_bag_dir_name = File.basename(package.path)
      logger.debug("Inner bag name: #{inner_bag_dir_name}")
      ingest_dir_name = inner_bag_dir_name.gsub("-" + package.uuid, "")
      logger.debug("Directory name on Archivematica ingest: #{ingest_dir_name}")
      object_metadata = RepositoryData::ObjectMetadata.new(
        id: package.uuid,
        title: "#{package.uuid} / #{ingest_dir_name}",
        creator: NA,
        description: NA
      )
      RepositoryData::RepositoryPackageData.new(
        remote_path: package.path,
        metadata: object_metadata,
        context: @name,
        stored_time: Time.parse(package.stored_date)
      )
    end
    private :create_package_data_object

    def get_package_data_object(package_id)
      package = @api.get_package(package_id)
      package && create_package_data_object(package)
    end

    def get_package_data_objects(stored_date:, package_filter: AllPackageFilter.new)
      logger.info("Archivematica instance: #{@name}")
      packages = @api.get_packages(location_uuid: @location_uuid, stored_date: stored_date)
      filtered_packages = package_filter.filter(packages)
      filtered_packages.map { |package| create_package_data_object(package) }
    end
  end
end
