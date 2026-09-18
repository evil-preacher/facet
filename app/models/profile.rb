class Profile < ApplicationRecord
  GENDERS = %w[male female non_binary prefer_not_to_say].freeze

  belongs_to :user

  enum :gender, GENDERS.index_with(&:itself), validate: true

  validates :first_name, :last_name, :gender, presence: true
  validates :user_id, uniqueness: true
  validate :birth_date_cannot_be_in_the_future

  private

  def birth_date_cannot_be_in_the_future
    errors.add(:birth_date, :future) if birth_date.present? && birth_date > Date.current
  end
end
