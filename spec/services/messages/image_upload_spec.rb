require "rails_helper"

RSpec.describe Messages::ImageUpload do
  ImageUploadStub = Struct.new(:data, :original_filename) do
    def read(length)
      data.byteslice(0, length)
    end

    def rewind; end
  end

  it "detects JPEG from bytes instead of trusting the filename" do
    upload = ImageUploadStub.new("\xFF\xD8\xFFphoto".b, "../../portrait.png")

    result = described_class.call(upload)

    expect(result).to have_attributes(
      content_type: "image/jpeg",
      extension: "jpg",
      original_filename: "portrait.png"
    )
  end

  it "rejects unsupported bytes" do
    upload = ImageUploadStub.new("not an image".b, "photo.jpg")

    expect { described_class.call(upload) }.to raise_error(Ai::ValidationError)
  end

  it "rejects files larger than ten megabytes" do
    upload = ImageUploadStub.new("\xFF\xD8\xFF".b + ("x" * MessageAttachment::MAX_BYTES), "photo.jpg")

    expect { described_class.call(upload) }.to raise_error(Ai::ValidationError)
  end
end
