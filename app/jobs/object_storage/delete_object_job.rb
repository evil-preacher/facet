module ObjectStorage
  class DeleteObjectJob < ApplicationJob
    queue_as :maintenance

    def perform(key)
      S3Store.default.delete(key: key)
    end
  end
end
