require "semantic_logger"

require_relative "api_backend"
require_relative "bag_status"

module APTrust
  module IngestStatus
    CANCELLED = "cancelled"
    FAILED = "failed"
    NOT_FOUND = "not found"
    PROCESSING = "processing"
    SUCCESS = "success"
  end

  class APTrustAPI
    include SemanticLogger::Loggable

    API_V3 = "/member-api/v3/"
    DEFAULT_OBJECT_ID_PREFIX = "umich.edu/"
    BUFFER = 60

    def initialize(api_backend:, api_prefix: API_V3, object_id_prefix: DEFAULT_OBJECT_ID_PREFIX)
      @backend = api_backend
      @api_prefix = api_prefix
      @object_id_prefix = object_id_prefix
    end

    def self.from_config(
      base_url:,
      username:,
      api_key:,
      api_backend: APIBackend::FaradayAPIBackend,
      api_prefix: API_V3,
      object_id_prefix: DEFAULT_OBJECT_ID_PREFIX
    )
      backend = api_backend.new(
        base_url: "#{base_url}#{api_prefix}",
        headers: {
          :accept => "application/json",
          :content_type => "application/json",
          "X-Pharos-API-User" => username,
          "X-Pharos-API-Key" => api_key
        }
      )
      new(api_backend: backend, api_prefix: api_prefix, object_id_prefix: object_id_prefix)
    end

    def get_ingest_status(bag_identifier:, deposited_at:)
      # Modelled after https://github.com/mlibrary/heliotrope/blob/master/app/services/aptrust/service.rb
      # See also https://aptrust.github.io/registry/#/Work%20Items
      time_filter = (deposited_at - BUFFER).strftime("%Y-%m-%dT%H:%M:%S.%6N")
      data = @backend.get("items", {
        object_identifier: @object_id_prefix + bag_identifier,
        action: "Ingest",
        date_processed__gteq: time_filter,
        per_page: 1,
        sort: "date_processed__desc"
      })
      logger.debug(data)
      return IngestStatus::NOT_FOUND if data["results"].nil?
      first_result = data["results"][0]
      status = first_result["status"]
      stage = first_result["stage"]

      if /failed/i.match?(status)
        IngestStatus::FAILED
      elsif /cancelled/i.match?(status)
        IngestStatus::CANCELLED
      elsif /success/i.match?(status) && /cleanup/i.match?(stage)
        IngestStatus::SUCCESS
      else
        IngestStatus::PROCESSING
      end
    end
  end

  class APTrustVerifier
    include SemanticLogger::Loggable

    def initialize(aptrust_api:, status_event_repo:)
      @aptrust_api = aptrust_api
      @status_event_repo = status_event_repo
    end

    def verify(bag_identifier:, deposited_at:)
      status = @aptrust_api.get_ingest_status(
        bag_identifier: bag_identifier,
        deposited_at: deposited_at
      )
      logger.debug("Ingest status from APTrust: #{status}")
      log_message_beginning = "Deposit for bag #{bag_identifier}"
      case status
      when APTrust::IngestStatus::SUCCESS
        @status_event_repo.create(
          bag_identifier: bag_identifier,
          status: BagStatus::VERIFIED,
          timestamp: Time.now.utc,
          note: "Ingest to APTrust verified"
        )
        logger.info("#{log_message_beginning} was verified.")
      when APTrust::IngestStatus::FAILED, APTrust::IngestStatus::CANCELLED
        @status_event_repo.create(
          bag_identifier: bag_identifier,
          status: BagStatus::VERIFY_FAILED,
          timestamp: Time.now.utc,
          note: "Ingest to APTrust failed with status \"#{status}\""
        )
        logger.error("#{log_message_beginning} failed.")
      when APTrust::IngestStatus::NOT_FOUND
        logger.info("#{log_message_beginning} was not yet found.")
      when APTrust::IngestStatus::PROCESSING
        logger.info("#{log_message_beginning} is still being processed.")
      end
    end
  end
end
