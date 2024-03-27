module RepositoryData
  RepositoryPackageData = Struct.new(
    "RepositoryPackageData",
    :remote_path,
    :metadata,
    :stored_time,
    keyword_init: true
  )

  ObjectMetadata = Struct.new(
    "ObjectMetadata",
    :id,
    :title,
    :creator,
    :description,
    keyword_init: true
  )
end
