module Messages
  class ImageUpload
    Result = Data.define(:bytes, :content_type, :extension, :original_filename)

    SIGNATURES = {
      "image/jpeg" => ->(bytes) { bytes.start_with?("\xFF\xD8\xFF".b) },
      "image/png" => ->(bytes) { bytes.start_with?("\x89PNG\r\n\x1A\n".b) },
      "image/webp" => ->(bytes) {
        bytes.bytesize >= 12 && bytes.start_with?("RIFF") && bytes.byteslice(8, 4) == "WEBP"
      }
    }.freeze
    EXTENSIONS = {
      "image/jpeg" => "jpg",
      "image/png" => "png",
      "image/webp" => "webp"
    }.freeze

    def self.call(upload)
      new(upload).call
    end

    def initialize(upload)
      @upload = upload
    end

    def call
      bytes = read_bytes
      content_type = SIGNATURES.find { |_type, matcher| matcher.call(bytes) }&.first
      raise Ai::ValidationError, "Unsupported image format" unless content_type
      raise Ai::ValidationError, "Image is empty" if bytes.empty?
      if bytes.bytesize > MessageAttachment::MAX_BYTES
        raise Ai::ValidationError, "Image exceeds 10 MB"
      end

      Result.new(
        bytes: bytes,
        content_type: content_type,
        extension: EXTENSIONS.fetch(content_type),
        original_filename: sanitized_filename
      )
    end

    private

    attr_reader :upload

    def read_bytes
      upload.rewind if upload.respond_to?(:rewind)
      upload.read(MessageAttachment::MAX_BYTES + 1).to_s.b
    ensure
      upload.rewind if upload.respond_to?(:rewind)
    end

    def sanitized_filename
      name = File.basename(upload.original_filename.to_s).presence
      name&.truncate(255, omission: "")
    end
  end
end
