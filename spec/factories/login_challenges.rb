FactoryBot.define do
  factory :login_challenge do
    association :user, :confirmed
    token { SecureRandom.urlsafe_base64(24) }
    code_digest { LoginChallenge.digest(token, "123456") }
    expires_at { LoginChallenge::CODE_TTL.from_now }
    requested_ip { FFaker::Internet.ip_v4_address }
  end
end
