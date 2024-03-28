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

require_relative "lib/aptrust"
require_relative "lib/bag_repository"
require_relative "lib/status_event_repository"
require_relative "lib/bag_status"

class APTrustVerificationError < StandardError
end

class APTrustVerificationJob
  include SemanticLogger::Loggable

  def initialize(config)
    aptrust_api = APTrust::APTrustAPI.from_config(
      base_url: config.aptrust.api.base_url,
      username: config.aptrust.api.username,
      api_key: config.aptrust.api.api_key
    )
    @bag_repo = BagRepository::BagRepositoryFactory.for(use_db: DB)
    @status_event_repo = StatusEventRepository::StatusEventRepositoryFactory.for(use_db: DB)
    @verifier = APTrust::APTrustVerifier.new(
      aptrust_api: aptrust_api, status_event_repo: @status_event_repo
    )
  end

  def process
    @bag_repo.get_all.each do |bag|
      logger.debug(bag)
      latest_event = @status_event_repo.get_latest_event_for_bag(bag_identifier: bag.identifier)
      logger.debug(latest_event)
      next if latest_event&.status != BagStatus::DEPOSITED

      logger.info("Deposit with pending verification found for bag #{bag.identifier}.")
      @verifier.verify(bag_identifier: bag.identifier, deposited_at: latest_event.timestamp)
    end
  end
end

APTrustVerificationJob.new(config).process
