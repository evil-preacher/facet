require "pathname"

namespace :ai do
  namespace :prompts do
    desc "Import missing prompt revisions from a private directory"
    task import: :environment do
      directory = ENV.fetch("DIRECTORY") { abort "Set DIRECTORY to the private prompt directory" }
      path = Pathname.new(directory)
      abort "Prompt directory does not exist: #{path}" unless path.directory?

      keys = Ai::PromptCatalog::KEYS
      missing_files = keys.reject { |key| path.join("#{key}.txt").file? }
      abort "Missing prompt files: #{missing_files.join(', ')}" if missing_files.any?

      contents = keys.to_h { |key| [ key, path.join("#{key}.txt").read.strip ] }
      abort "Prompt files must not be blank" if contents.value?("")

      imported = []
      AiPromptRevision.transaction do
        contents.each do |key, content|
          next if Ai::PromptCatalog.active(key)

          Ai::PromptCatalog.publish(key: key, content: content)
          imported << key
        end
      end
      puts "Imported #{imported.length} missing prompts; #{keys.length - imported.length} already active."
    end
  end
end
