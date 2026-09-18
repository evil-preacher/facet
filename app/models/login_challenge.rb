class LoginChallenge < ApplicationRecord
  CODE_TTL = 10.minutes
  MAX_ATTEMPTS = 5
  RESEND_INTERVAL = 1.minute

  belongs_to :user

  scope :active, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  validates :token, :code_digest, :expires_at, presence: true
  validates :token, uniqueness: true
  validates :attempts_count, numericality: { greater_than_or_equal_to: 0 }

  def self.issue_for!(user:, requested_ip:)
    transaction do
      user.login_challenges.active.update_all(consumed_at: Time.current, updated_at: Time.current)

      code = format("%06d", SecureRandom.random_number(1_000_000))
      token = SecureRandom.urlsafe_base64(24)
      challenge = user.login_challenges.create!(
        token: token,
        code_digest: digest(token, code),
        expires_at: CODE_TTL.from_now,
        requested_ip: requested_ip
      )

      [ challenge, code ]
    end
  end

  def verify(code)
    with_lock do
      return false unless usable?

      self.attempts_count += 1
      valid = ActiveSupport::SecurityUtils.secure_compare(
        code_digest,
        self.class.digest(token, code.to_s.strip)
      )
      self.consumed_at = Time.current if valid
      save!
      valid
    end
  end

  def usable?
    consumed_at.nil? && expires_at.future? && attempts_count < MAX_ATTEMPTS
  end

  def self.digest(token, code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{token}:#{code}")
  end
end
