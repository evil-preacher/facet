module ApplicationHelper
  def gender_options
    Profile::GENDERS.map { |gender| [ t("app.genders.#{gender}"), gender ] }
  end

  def personality_avatar_url(personality)
    return unless personality.avatar_object_key.present?

    ObjectStorage::S3Store.default.presigned_url(key: personality.avatar_object_key)
  rescue StandardError => error
    Rails.logger.warn(
      "Could not create avatar URL personality_id=#{personality.id} " \
      "error=#{error.class.name}"
    )
    nil
  end

  def message_image_url(message_image)
    return unless message_image&.status_ready? && message_image.object_key.present?

    ObjectStorage::S3Store.default.presigned_url(key: message_image.object_key)
  rescue StandardError => error
    Rails.logger.warn(
      "Could not create message image URL message_image_id=#{message_image.id} " \
      "error=#{error.class.name}"
    )
    nil
  end

  def message_attachment_url(attachment)
    return unless attachment&.object_key.present?

    ObjectStorage::S3Store.default.presigned_url(key: attachment.object_key)
  rescue StandardError => error
    Rails.logger.warn(
      "Could not create attachment URL message_attachment_id=#{attachment.id} " \
      "error=#{error.class.name}"
    )
    nil
  end
end
