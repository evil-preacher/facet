class User < ApplicationRecord
  CONFIRMATION_TOKEN_TTL = 24.hours
  CONFIRMATION_RESEND_INTERVAL = 1.minute

  has_one :profile, dependent: :destroy
  has_many :login_challenges, dependent: :destroy
  has_many :personalities, dependent: :destroy
  has_many :model_calls, dependent: :restrict_with_exception

  before_validation :normalize_email

  validates :email,
            presence: true,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: { case_sensitive: false }

  def self.normalize_email(email)
    email.to_s.strip.downcase
  end

  def confirmed?
    confirmed_at.present?
  end

  def confirmation_token
    signed_id(purpose: :email_confirmation, expires_in: CONFIRMATION_TOKEN_TTL)
  end

  def confirmation_email_available?
    confirmation_sent_at.nil? || confirmation_sent_at < CONFIRMATION_RESEND_INTERVAL.ago
  end

  def send_confirmation_email!
    return false unless confirmation_email_available?

    touch(:confirmation_sent_at)
    UserMailer.with(user: self).confirmation_email.deliver_now
    true
  end

  private

  def normalize_email
    self.email = self.class.normalize_email(email)
  end
end
