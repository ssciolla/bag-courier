require "time"

module BagTag
  class BagInfoBagTag
    KEY_SOURCE_ORG = "Source-Organization"
    KEY_COUNT = "Bag-Count"
    KEY_DATE = "Bagging-Date"
    KEY_INTERNAL_SENDER_ID = "Internal-Sender-Identifier"
    KEY_INTERNAL_SENDER_DESC = "Internal-Sender-Description"
    VALUE_SOURCE_ORG_DEFAULT = "University of Michigan"

    @@file_name = "bag-info.txt"

    def self.datetime_now
      now_datetime = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      Time.parse(now_datetime).iso8601
    end

    def initialize(
      identifier:,
      description:,
      bag_count: [1, 1],
      organization: VALUE_SOURCE_ORG_DEFAULT,
      extra_data: nil
    )
      @identifier = identifier
      @description = description
      @bag_count = bag_count
      @organization = organization
      @extra_data = extra_data
    end

    def data
      data = {
        KEY_SOURCE_ORG => @organization,
        KEY_COUNT => "#{@bag_count[0]} of #{@bag_count[1]}",
        KEY_DATE => BagInfoBagTag.datetime_now,
        KEY_INTERNAL_SENDER_ID => @identifier,
        KEY_INTERNAL_SENDER_DESC => @description
      }
      if @extra_data
        data = data.merge(@extra_data)
      end
      data
    end
  end

  class TagSerializer
    def initialize(data)
      @data = data
    end

    def serialize
      content = ""
      @data.each_pair do |k, v|
        content += "#{k}: #{v}\n"
      end
      content
    end

    def self.serialize(data)
      new(data).serialize
    end
  end

  class SerializableBagTag
    @@file_name = "default.txt"

    def serialize
      raise NotImplementedError
    end
  end

  class AptrustInfoBagTag < SerializableBagTag
    module StorageOption
      STANDARD = "Standard"
      GLACIER_DEEP_OR = "Glacier-Deep-OR"
    end

    module Access
      INSTITUTION = "Institution"
    end

    @@file_name = "aptrust-info.txt"
    @@default_description = "Bag deposited to APTrust"
    @@field_length = 255

    attr_reader :title,
      :item_description,
      :creator,
      :description,
      :access,
      :storage_option,
      :extra_data

    def file_name
      @@file_name
    end

    def self.squish(value)
      value.strip.gsub(/\s+/, " ")[0..(@@field_length - 1)]
    end

    def initialize(
      title:,
      item_description:,
      creator:,
      description: nil,
      access: Access::INSTITUTION,
      storage_option: StorageOption::STANDARD,
      extra_data: nil,
      serializer: TagSerializer
    )
      @title = AptrustInfoBagTag.squish(title)
      @description = AptrustInfoBagTag.squish(description || @@default_description)
      @item_description = AptrustInfoBagTag.squish(item_description)
      @creator = AptrustInfoBagTag.squish(creator)
      @access = access
      @storage_option = storage_option
      @extra_data = extra_data
      @serializer = serializer
    end

    def data
      data = {
        Title: @title,
        Description: @description,
        "Item Description": @item_description,
        "Creator/Author": @creator,
        Access: @access,
        "Storage-Option": @storage_option
      }
      if @extra_data
        data = data.merge(@extra_data)
      end
      data
    end

    def serialize
      @serializer.serialize(data)
    end
  end
end
