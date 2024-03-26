require "semantic_logger"
require "sequel"

require_relative "lib/config"

SemanticLogger.add_appender(io: $stderr, formatter: :color)
config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))
SemanticLogger.default_level = config.settings.log_level

DB = config.database && Sequel.connect(
  adapter: "mysql2",
  host: config.database.host,
  port: config.database.port,
  database: config.database.database,
  user: config.database.user,
  password: config.database.password,
  fractional_seconds: true
)

require_relative "lib/archivematica"
require_relative "lib/bag_repository"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"
require_relative "lib/remote_client"
require_relative "lib/repository_package_repository"
require_relative "lib/status_event_repository"

class DarkBlueJob
  include SemanticLogger::Loggable

  module ExtraBagInfoData
    CONTENT_TYPE_KEY = "Dark-Blue-Content-Type"
    LOCATION_UUID_KEY = "Archivematica-Location-UUID"
  end

  def initialize(config)
    @package_repo = RepositoryPackageRepository::RepositoryPackageRepositoryFactory.for(use_db: DB)
    @dispatcher = Dispatcher::APTrustDispatcher.new(
      settings: config.settings,
      repository: config.repository,
      target_client: RemoteClient::RemoteClientFactory.from_config(
        type: config.target_remote.type,
        settings: config.target_remote.settings
      ),
      status_event_repo: StatusEventRepository::StatusEventRepositoryFactory.for(use_db: DB),
      bag_repo: BagRepository::BagRepositoryFactory.for(use_db: DB)
    )
    @arch_configs = config.dark_blue.archivematicas
    @object_size_limit = config.settings.object_size_limit
  end

  def process
    @arch_configs.each do |arch_config|
      api_config = arch_config.api
      arch_api = Archivematica::ArchivematicaAPI.from_config(
        base_url: api_config.base_url,
        api_key: api_config.api_key,
        username: api_config.username
      )
      remote_config = arch_config.remote
      remote_client = RemoteClient::RemoteClientFactory.from_config(
        type: remote_config.type,
        settings: remote_config.settings
      )

      max_updated_at = @package_repo.get_max_updated_at_for_repository(arch_config.repository_name)

      package_data_objs = Archivematica::ArchivematicaService.new(
        name: arch_config.name,
        api: arch_api,
        location_uuid: api_config.location_uuid,
        stored_date: max_updated_at,
        **(@object_size_limit ? {package_filter: Archivematica::SizePackageFilter.new(@object_size_limit)} : {})
      ).get_package_data_objects

      extra_bag_info = {
        ExtraBagInfoData::CONTENT_TYPE_KEY => arch_config.name,
        ExtraBagInfoData::LOCATION_UUID_KEY => api_config.location_uuid
      }

      package_data_objs.each do |package_data|
        logger.debug(package_data)
        created = @package_repo.create(
          identifier: package_data.metadata.id,
          repository_name: arch_config.repository_name,
          updated_at: package_data.stored_time
        )
        if !created
          @package_repo.update_updated_at(
            identifier: package_data.metadata.id,
            updated_at: package_data.stored_time
          )
        end

        courier = @dispatcher.dispatch(
          object_metadata: package_data.metadata,
          data_transfer: DataTransfer::RemoteClientDataTransfer.new(
            remote_client: remote_client,
            remote_path: package_data.remote_path
          ),
          context: package_data.context,
          extra_bag_info: extra_bag_info
        )
        courier.deliver
      end
    end
  end
end

DarkBlueJob.new(config).process
