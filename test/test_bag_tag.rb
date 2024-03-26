require "logger"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/bag_tag"

LOGGER = Logger.new($stdout)

class BagInfoBagTagTest < Minitest::Test
  def setup
    @time = Time.new(2023, 12, 7, 12, 0, 0, "UTC")
  end

  def test_bag_info_tag_data
    Time.stub :now, @time do
      bag_info = BagTag::BagInfoBagTag.new(
        identifier: "5494124",
        description: "Bag from repository X containing item to be preserved"
      )
      expected = {
        "Source-Organization" => "University of Michigan",
        "Bag-Count" => "1 of 1",
        "Bagging-Date" => "2023-12-07T12:00:00Z",
        "Internal-Sender-Identifier" => "5494124",
        "Internal-Sender-Description" => "Bag from repository X containing item to be preserved"
      }
      assert_equal expected, bag_info.data
    end
  end

  def test_bag_info_tag_data_without_defaults
    Time.stub :now, @time do
      bag_info = BagTag::BagInfoBagTag.new(
        identifier: "2124796",
        description: "Bag from repository X containing item to be preserved",
        bag_count: [2, 3],
        organization: "Mythical University",
        extra_data: {"Context" => "Some important detail"}
      )
      expected = {
        "Source-Organization" => "Mythical University",
        "Bag-Count" => "2 of 3",
        "Bagging-Date" => "2023-12-07T12:00:00Z",
        "Internal-Sender-Identifier" => "2124796",
        "Internal-Sender-Description" => "Bag from repository X containing item to be preserved",
        "Context" => "Some important detail"
      }
      assert_equal expected, bag_info.data
    end
  end
end

class AptrustInfoBagTagTest < Minitest::Test
  def setup
    @base_test_data = {
      title: "Some Object",
      description: "A bag from a repository containing preserved item",
      item_description: "An item being preserved",
      creator: "Not available"
    }
  end

  def test_aptrust_tag_serialize
    aptrust_info = BagTag::AptrustInfoBagTag.new(**@base_test_data)
    expected = <<~TEXT
      Title: Some Object
      Description: A bag from a repository containing preserved item
      Item Description: An item being preserved
      Creator/Author: Not available
      Access: Institution
      Storage-Option: Standard
    TEXT
    assert_equal expected, aptrust_info.serialize
  end

  def test_aptrust_tag_serialize_with_no_data_defaults
    test_data = @base_test_data.merge({
      access: "Consortia",
      storage_option: "Glacier-Deep-OR",
      extra_data: {"Context" => "Some important detail"}
    })
    aptrust_info = BagTag::AptrustInfoBagTag.new(**test_data)
    expected = <<~TEXT
      Title: Some Object
      Description: A bag from a repository containing preserved item
      Item Description: An item being preserved
      Creator/Author: Not available
      Access: Consortia
      Storage-Option: Glacier-Deep-OR
      Context: Some important detail
    TEXT
    assert_equal expected, aptrust_info.serialize
  end

  def test_aptrust_info_tag_squish
    text = <<~TEXT
      The quick brown fox jumps over the lazy dog.  The quick brown fox jumps over the lazy dog.
      The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog.   
      The quick brown fox jumps over the lazy dog.     The quick brown fox jumps over the lazy dog.
      The quick brown fox jumps over the lazy dog.
    TEXT

    expected = ("The quick brown fox jumps over the lazy dog. " * 5) +  # 225
      "The quick brown fox jumps over"  # 30
    assert_equal expected, BagTag::AptrustInfoBagTag.squish(text)
  end
end
