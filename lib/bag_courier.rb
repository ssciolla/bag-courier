require "minitar"
require "semantic_logger"

require_relative "bag_adapter"
require_relative "remote_client"
require_relative "bag_status"

module BagCourier
  class BagId
    attr_reader :repository, :object_id, :context, :part_id

    def initialize(repository:, object_id:, context: nil, part_id: nil)
      @repository = repository
      @context = context
      @object_id = object_id
      @part_id = part_id
    end

    def to_s
      segments = [@context, @object_id, @part_id].select { |segment| !segment.nil? }
      "#{@repository}.#{segments.join "-"}"
    end
  end

  class BagCourier
    include SemanticLogger::Loggable

    EXT_TAR = ".tar"

    attr_reader :bag_id, :status_event_repo

    def initialize(
      bag_id:,
      bag_info:,
      tags:,
      data_transfer:,
      target_client:,
      working_dir:,
      export_dir:,
      dry_run:,
      status_event_repo:,
      validator:
    )
      @bag_id = bag_id
      @bag_info = bag_info
      @tags = tags

      @data_transfer = data_transfer
      @target_client = target_client
      @status_event_repo = status_event_repo

      @working_dir = working_dir
      @export_dir = export_dir
      @dry_run = dry_run
      @validator = validator
    end

    def track!(status:, note: nil)
      @status_event_repo.create(
        bag_identifier: @bag_id.to_s,
        status: status,
        timestamp: Time.now.utc,
        note: note
      )
    end

    def tar(target_path)
      logger.debug(["target_path=#{target_path}", "bag_id=#{@bag_id}"])

      parent = File.dirname target_path
      Dir.chdir(parent) do
        tar_src = File.basename target_path
        tar_file = File.basename(target_path) + EXT_TAR
        logger.debug([
          "target_path=#{target_path}",
          "parent=#{parent}",
          "tar_src=#{tar_src}",
          "tar_file=#{tar_file}"
        ])
        track!(status: BagStatus::PACKING)
        Minitar.pack(tar_src, File.open(tar_file, "wb"))
        track!(status: BagStatus::PACKED)
      end
      new_path = target_path + EXT_TAR
      logger.debug([
        "target_path=#{target_path}",
        "bag_id=#{@bag_id}",
        "new_path=#{new_path}"
      ])
      new_path
    end

    def deposit(file_path:)
      logger.debug(["file_path=#{file_path}", "bag_id=#{@bag_id}"])

      logger.debug("dry_run=#{@dry_run}")
      if @dry_run
        track!(status: BagStatus::DEPOSIT_SKIPPED)
        return
      end

      logger.info("Sending bag to #{@target_client.remote_text}")
      # add timing
      track!(status: BagStatus::DEPOSITING)
      @target_client.send_file(local_file_path: file_path)
      track!(status: BagStatus::DEPOSITED)
    end

    def deliver
      logger.debug("bag_id=#{@bag_id}")

      begin
        track!(status: BagStatus::BAGGING)
        bag_path = File.join(@working_dir, @bag_id.to_s)
        bag = BagAdapter::BagAdapter.new(bag_path)

        track!(status: BagStatus::COPYING)
        @data_transfer.transfer(bag.data_dir)
        track!(status: BagStatus::COPIED)

        if @validator
          track!(status: BagStatus::VALIDATING)
          @validator.validate(bag.data_dir)
          track!(status: BagStatus::VALIDATED)
        else
          track!(status: BagStatus::VALIDATION_SKIPPED)
        end

        @tags.each do |tag|
          bag.add_tag_file!(
            tag_file_text: tag.serialize,
            file_name: tag.file_name
          )
        end
        bag.add_bag_info(@bag_info.data)
        bag.add_manifests
        track!(status: BagStatus::BAGGED, note: "bag_path: #{bag_path}")

        tar_file_path = tar(bag.bag_dir)
        export_tar_file_path = File.join(@export_dir, File.basename(tar_file_path))
        logger.debug([
          "export_dir=#{@export_dir}",
          "tar_file_path=#{tar_file_path}",
          "export_tar_file_path=#{export_tar_file_path}"
        ])
        FileUtils.mv(tar_file_path, export_tar_file_path)
        FileUtils.rm_r(bag.bag_dir)

        deposit(file_path: export_tar_file_path)
      rescue => e
        note = "failed with error #{e.class}: #{e.full_message}"
        track!(status: BagStatus::FAILED, note: note)
        logger.error("BagCourier.deliver #{note}")
      end
    end
  end
end
