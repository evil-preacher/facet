require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  let(:user) { User.create!(email: "person@example.com") }

  it "renders a confirmation email" do
    mail = described_class.with(user: user).confirmation_email

    expect(mail.to).to eq([ user.email ])
    expect(mail.subject).to eq("Confirm your email for Facet")
    expect(mail.text_part.body.decoded).to include("email/confirmation")
  end

  it "renders an English confirmation email" do
    I18n.with_locale(:en) do
      mail = described_class.with(user: user).confirmation_email

      expect(mail.subject).to eq("Confirm your email for Facet")
      expect(mail.text_part.body.decoded).to include("Follow this link")
    end
  end

  it "renders a login code email" do
    mail = described_class.with(user: user, code: "123456").login_code

    expect(mail.to).to eq([ user.email ])
    expect(mail.text_part.body.decoded).to include("123456")
  end
end
