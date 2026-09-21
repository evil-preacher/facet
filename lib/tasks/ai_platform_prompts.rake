require "pathname"

namespace :ai do
  namespace :platform_prompts do
    desc "Publish a provider-specific administrative prompt from FILE"
    task publish: :environment do
      provider = ENV.fetch("PROVIDER")
      purpose = ENV.fetch("PURPOSE", "conversation")
      path = Pathname.new(ENV.fetch("FILE")).expand_path
      prompt = Ai::PlatformPrompts::Publish.call(
        provider: provider,
        purpose: purpose,
        content: path.read
      )

      puts "Published #{prompt.provider}/#{prompt.purpose} revision #{prompt.revision} (#{prompt.checksum})"
    end
  end
end
