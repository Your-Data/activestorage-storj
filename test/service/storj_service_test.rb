# frozen_string_literal: true

require "service/shared_service_tests"

if SERVICE_CONFIGURATIONS[:storj]
  class ActiveStorage::Service::StorjServiceTest < ActiveSupport::TestCase
    SERVICE = ActiveStorage::Service.configure(:storj, SERVICE_CONFIGURATIONS)

    include ActiveStorage::Service::SharedServiceTests

    test "name" do
      assert_equal :storj, @service.name
    end

    test "linkshare URL generation" do
      url = @service.url(@key, expires_in: 5.minutes)

      assert_match(/#{@link_sharing_address}\/raw\/[a-z].*\/#{@service.bucket}\/#{@key}/, url)
    end

    test "upload a zero byte file" do
      key  = SecureRandom.base58(24)
      data = ""
      @service.upload(key, StringIO.new(data), checksum: OpenSSL::Digest::MD5.base64digest(data))

      assert_equal data, @service.download(key)
    ensure
      @service.delete key
    end

    test "upload with content type" do
      key          = SecureRandom.base58(24)
      data         = "Something else entirely!"
      content_type = "text/plain"

      @service.upload(
        key,
        StringIO.new(data),
        checksum: OpenSSL::Digest::MD5.base64digest(data),
        filename: "cool_data.txt",
        content_type: content_type
      )

      assert_equal content_type, @service.object(key).custom["content-type"]
    ensure
      @service.delete key
    end

    test "upload with custom_metadata" do
      key      = SecureRandom.base58(24)
      data     = "Something else entirely!"
      @service.upload(
        key,
        StringIO.new(data),
        checksum: Digest::MD5.base64digest(data),
        content_type: "text/plain",
        custom_metadata: { "foo" => "baz" },
        filename: "custom_metadata.txt"
      )

      assert_equal "baz", @service.object(key).custom["foo"]
    ensure
      @service.delete key
    end

    test "upload with content disposition" do
      key  = SecureRandom.base58(24)
      data = "Something else entirely!"

      @service.upload(
        key,
        StringIO.new(data),
        checksum: OpenSSL::Digest::MD5.base64digest(data),
        filename: ActiveStorage::Filename.new("cool_data.txt"),
        disposition: :attachment
      )

      assert_equal("attachment; filename=\"cool_data.txt\"; filename*=UTF-8''cool_data.txt", @service.object(key).custom["content-disposition"])
    ensure
      @service.delete key
    end

    test "uploading a large object in multiple parts" do
      key  = SecureRandom.base58(24)
      data = SecureRandom.bytes(8.megabytes)

      @service.upload key, StringIO.new(data), checksum: OpenSSL::Digest::MD5.base64digest(data)
      assert data == @service.download(key)
    ensure
      @service.delete key
    end

    test "uploading a small object with multipart_upload_threshold configured" do
      service = build_service(multipart_upload_threshold: 6.megabytes)

      key  = SecureRandom.base58(24)
      data = SecureRandom.bytes(5.megabytes)

      service.upload key, StringIO.new(data), checksum: OpenSSL::Digest::MD5.base64digest(data)
      assert data == service.download(key)
    ensure
      service.delete key
    end

    test "update custom_metadata" do
      key      = SecureRandom.base58(24)
      data     = "Something else entirely!"
      @service.upload(key, StringIO.new(data), checksum: OpenSSL::Digest::MD5.base64digest(data), disposition: :attachment, filename: ActiveStorage::Filename.new("test.html"), content_type: "text/html", custom_metadata: { "foo" => "baz" })

      @service.update_metadata(key, disposition: :inline, filename: ActiveStorage::Filename.new("test.txt"), content_type: "text/plain", custom_metadata: { "foo" => "bar" })

      object = @service.object(key)
      assert_equal "text/plain", object.custom["content-type"]
      assert_match(/inline;.*test.txt/, object.custom["content-disposition"])
      assert_equal "bar", object.custom["foo"]
    ensure
      @service.delete key
    end

    private
      def build_service(configuration = {})
        ActiveStorage::Service.configure :storj, SERVICE_CONFIGURATIONS.deep_merge(storj: configuration)
      end
  end
else
  puts "Skipping Storj Service tests because no storj configuration was supplied"
end
