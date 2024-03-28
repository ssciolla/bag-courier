require "semantic_logger"
require_relative "bag_status"
require_relative "../db/database_schema" if DB

Sequel.default_timezone = :utc

module StatusEventRepository
  class UnknownStatusError < StandardError
  end

  class StatusEventRepositoryError < StandardError
  end

  StatusEvent = Struct.new(
    "StatusEvent",
    :id,
    :bag_identifier,
    :status,
    :timestamp,
    :note,
    keyword_init: true
  )

  class StatusEventRepositoryBase
    def create(bag_identifier:, status:, timestamp:, note: nil)
      raise NotImplementedError
    end

    def get_all
      raise NotImplementedError
    end

    def get_all_for_bag_identifier(identifier)
      raise NotImplementedError
    end

    def get_latest_event_for_bag(bag_identifier:)
      raise NotImplementedError
    end
  end

  class StatusEventInMemoryRepository < StatusEventRepositoryBase
    attr_reader :status_events

    def initialize
      @id = 0
      @status_events = []
    end

    def get_next_id!
      id = @id
      @id += 1
      id
    end
    private :get_next_id!

    def create(bag_identifier:, status:, timestamp:, note: nil)
      if !BagStatus.check_status?(status)
        raise UnknownStatusError
      end
      event = StatusEvent.new(
        id: get_next_id!,
        bag_identifier: bag_identifier,
        status: status,
        timestamp: timestamp,
        note: note
      )
      @status_events << event
    end

    def get_by_id(id)
      @status_events.find { |e| e.id == id }
    end

    def get_all
      @status_events
    end

    def get_all_for_bag_identifier(identifier)
      @status_events.select { |e| e.bag_identifier == identifier }
    end

    def get_latest_event_for_bag(bag_identifier:)
      events = @status_events
        .select { |e| e.bag_identifier == bag_identifier }
        .sort_by(&:timestamp).reverse
      (events.length > 0) ? events[0] : nil
    end
  end

  class StatusEventDatabaseRepository
    include SemanticLogger::Loggable

    def find_or_create_status(status_name)
      DatabaseSchema::Status.find_or_create(name: status_name)
    end
    private :find_or_create_status

    def create(bag_identifier:, status:, timestamp:, note: nil)
      if !BagStatus.check_status?(status)
        raise UnknownStatusError
      end
      status = find_or_create_status(status)

      bag = DatabaseSchema::Bag.first(identifier: bag_identifier)
      if !bag
        raise StatusEventRepositoryError, "Bag with #{bag_identifier} does not exist."
      end

      status_event = DatabaseSchema::StatusEvent.new(
        timestamp: timestamp, note: note
      )
      status_event.status = status
      status_event.bag = bag
      status_event.save
    end

    def convert_to_struct(status_event)
      StatusEvent.new(
        id: status_event.id,
        bag_identifier: status_event.bag.identifier,
        status: status_event.status.name,
        timestamp: status_event.timestamp,
        note: status_event.note
      )
    end
    private :convert_to_struct

    def base_query
      DatabaseSchema::StatusEvent.eager(:bag, :status)
    end
    private :base_query

    def get_all
      base_query.all.map { |se| convert_to_struct(se) }
    end

    def get_all_for_bag_identifier(identifier)
      base_query
        .where(bag: DatabaseSchema::Bag.where(identifier: identifier))
        .all
        .map { |se| convert_to_struct(se) }
    end

    def get_latest_event_for_bag(bag_identifier:)
      event = base_query
        .where(bag: DatabaseSchema::Bag.where(identifier: bag_identifier))
        .order(Sequel.desc(:timestamp))
        .first
      event && convert_to_struct(event)
    end
  end

  class StatusEventRepositoryFactory
    def self.for(use_db:)
      use_db ? StatusEventDatabaseRepository.new : StatusEventInMemoryRepository.new
    end
  end
end
