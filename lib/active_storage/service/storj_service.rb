# frozen_string_literal: true

gem "uplink-ruby", "~> 1.0"

require "uplink"

module ActiveStorage
  MULTIPART_UPLOAD_THRESHOLD = 5.megabytes
  AUTH_SERVICE_ADDRESS = "auth.storjshare.io:7777"
  LINK_SHARING_ADDRESS = "https://link.storjshare.io"

  # = Active Storage \Storj \Service
  #
  # Wraps the Storj as an Active Storage service.
  # See ActiveStorage::Service for the generic API documentation that applies to all services.
  class Service::StorjService < Service
    attr_reader :bucket

    def initialize(access_grant:, bucket:, upload_chunk_size: nil, download_chunk_size: nil, multipart_upload_threshold: nil,
      auth_service_address: nil, link_sharing_address: nil, public: false, **config)
      @access_grant = access_grant
      @bucket = bucket
      @upload_chunk_size = upload_chunk_size || MULTIPART_UPLOAD_THRESHOLD
      @download_chunk_size = download_chunk_size || MULTIPART_UPLOAD_THRESHOLD
      @multipart_upload_threshold = [multipart_upload_threshold || MULTIPART_UPLOAD_THRESHOLD, MULTIPART_UPLOAD_THRESHOLD].max
      @auth_service_address = auth_service_address || AUTH_SERVICE_ADDRESS
      @link_sharing_address = link_sharing_address || LINK_SHARING_ADDRESS
      @public = public
      @config = config
    end

    def upload(key, io, checksum: nil, content_type: nil, disposition: nil, filename: nil, custom_metadata: {})
      instrument :upload, key: key, checksum: checksum do
        contents = io.read

        if checksum.present?
          md5_hash = OpenSSL::Digest::MD5.base64digest(contents)
          raise ActiveStorage::IntegrityError if md5_hash != checksum
        end

        Uplink.parse_access(@access_grant) do |access|
          access.open_project do |project|
            project.ensure_bucket(@bucket)

            content_disposition = content_disposition_with(type: disposition, filename: filename) if disposition && filename

            upload_object(project, key, contents, content_type, content_disposition, custom_metadata)
          end
        end
      end
    end

    def update_metadata(key, content_type:, disposition: nil, filename: nil, custom_metadata: {})
      instrument :update_metadata, key: key, content_type: content_type, disposition: disposition do
        Uplink.parse_access(@access_grant) do |access|
          access.open_project do |project|
            content_disposition = content_disposition_with(type: disposition, filename: filename) if disposition && filename

            project.update_object_metadata(@bucket, key, custom_metadata.merge({ "content-type": content_type, "content-disposition": content_disposition }))
          end
        end
      end
    end

    def download(key, &block)
      if block_given?
        instrument :streaming_download, key: key do
          stream(key, &block)
        end
      else
        instrument :download, key: key do
          Uplink.parse_access(@access_grant) do |access|
            access.open_project do |project|
              download_object(project, key)
            end
          end
        rescue Uplink::ObjectKeyNotFoundError
          raise ActiveStorage::FileNotFoundError
        end
      end
    end

    def download_chunk(key, range)
      instrument :download_chunk, key: key, range: range do
        Uplink.parse_access(@access_grant) do |access|
          access.open_project do |project|
            download_object(project, key, range)
          end
        end
      rescue Uplink::ObjectKeyNotFoundError
        raise ActiveStorage::FileNotFoundError
      end
    end

    def compose(source_keys, destination_key, filename: nil, content_type: nil, disposition: nil, custom_metadata: {})
      Uplink.parse_access(@access_grant) do |access|
        access.open_project do |project|

          contents = ''
          source_keys.each do |source_key|
            contents += download_object(project, source_key)
          end

          content_disposition = content_disposition_with(type: disposition, filename: filename) if disposition && filename

          upload_object(project, destination_key, contents, content_type, content_disposition, custom_metadata)
        end
      end
    end

    def delete(key)
      instrument :delete, key: key do
        Uplink.parse_access(@access_grant) do |access|
          access.open_project do |project|
            project.delete_object(@bucket, key)
          end
        end
      rescue Uplink::ObjectKeyNotFoundError
        # Ignore files already deleted
      end
    end

    def delete_prefixed(prefix)
      instrument :delete_prefixed, prefix: prefix do
        Uplink.parse_access(@access_grant) do |access|
          access.open_project do |project|
            objects = []

            project.list_objects(@bucket, { prefix: prefix }) do |it|
              while it.next?
                object = it.item
                project.delete_object(@bucket, object.key)
              end
            end
          end
        end
      end
    end

    def exist?(key)
      instrument :exist, key: key do |payload|
        Uplink.parse_access(@access_grant) do |access|
          access.open_project do |project|
            object = project.stat_object(@bucket, key)
            answer = object.key == key
            payload[:exist] = answer
            answer
          end
        end
      rescue Uplink::ObjectKeyNotFoundError
        answer = false
        payload[:exist] = answer
        answer
      end
    end

    def object(key)
      Uplink.parse_access(@access_grant) do |access|
        access.open_project do |project|
          project.stat_object(@bucket, key)
        end
      end
    rescue Uplink::ObjectKeyNotFoundError
      raise ActiveStorage::FileNotFoundError
    end

    def headers_for_direct_upload(key, content_type:, checksum:, filename: nil, disposition: nil, custom_metadata: {}, **)
      content_disposition = content_disposition_with(type: disposition, filename: filename) if disposition && filename

      { "Content-Type" => content_type, "Content-MD5" => checksum, "Content-Disposition" => content_disposition, **custom_metadata_headers(custom_metadata) }
    end

    private
      def upload_object(project, key, contents, content_type, content_disposition, custom_metadata = {})
        if contents.size <= @multipart_upload_threshold
          upload_with_single_part(project, key, contents, content_type, content_disposition, custom_metadata)
        else
          upload_with_multipart(project, key, contents, content_type, content_disposition, custom_metadata)
        end
      end

      def upload_with_single_part(project, key, contents, content_type, content_disposition, custom_metadata = {})
        project.upload_object(@bucket, key) do |upload|
          chunk_size = @upload_chunk_size

          file_size = contents.size
          uploaded_total = 0

          while uploaded_total < file_size
            upload_size_left = file_size - uploaded_total
            len = chunk_size <= 0 ? upload_size_left : [chunk_size, upload_size_left].min

            bytes_written = upload.write(contents[uploaded_total, len], len)
            uploaded_total += bytes_written
          end

          upload.set_custom_metadata(custom_metadata.merge({ "content-type": content_type, "content-disposition": content_disposition }))

          upload.commit
        end
      end

      def upload_with_multipart(project, key, contents, content_type, content_disposition, custom_metadata = {})
        file_size = contents.size
        part_size = @multipart_upload_threshold
        part_count = (file_size.to_f / @multipart_upload_threshold).ceil

        chunk_size = @upload_chunk_size
        uploaded_total = 0

        upload_info = project.begin_upload(@bucket, key)

        part_count.times do |i|
          project.upload_part(@bucket, key, upload_info.upload_id, i + 1) do |part_upload|
            upload_size = [(i + 1) * part_size, file_size].min

            while uploaded_total < upload_size
              upload_size_left = upload_size - uploaded_total
              len = chunk_size <= 0 ? upload_size_left : [chunk_size, upload_size_left].min

              bytes_written = part_upload.write(contents[uploaded_total, len], len)
              uploaded_total += bytes_written
            end

            part_upload.commit
          end
        end

        upload_options = {
          custom_metadata: custom_metadata.merge({ "content-type": content_type, "content-disposition": content_disposition })
        }
        project.commit_upload(@bucket, key, upload_info.upload_id, upload_options)
      end

      def download_object(project, key, range = nil)
        project.download_object(@bucket, key, range.present? ? { offset: range.begin, length: range.size } : nil) do |download|
          downloaded_data = []

          object = download.info
          file_size = object.content_length

          chunk_size = @download_chunk_size
          downloaded_total = 0

          loop do
            download_size_left = file_size - downloaded_total
            len = chunk_size <= 0 ? download_size_left : [chunk_size, download_size_left].min

            bytes_read, is_eof = download.read(downloaded_data, len)
            downloaded_total += bytes_read

            break if is_eof
          end

          downloaded_data.pack('C*')
        end
      end

      # Reads the object for the given key in chunks, yielding each to the block.
      def stream(key)
        Uplink.parse_access(@access_grant) do |access|
          access.open_project do |project|
            project.download_object(@bucket, key) do |download|
              object = download.info
              file_size = object.content_length

              chunk_size = @download_chunk_size
              downloaded_total = 0

              loop do
                download_size_left = file_size - downloaded_total
                len = chunk_size <= 0 ? download_size_left : [chunk_size, download_size_left].min

                downloaded_data = []
                bytes_read, is_eof = download.read(downloaded_data, len)
                downloaded_total += bytes_read

                break if is_eof

                yield downloaded_data.pack('C*')
              end
            end
          end
        end
      rescue Uplink::ObjectKeyNotFoundError
        raise ActiveStorage::FileNotFoundError
      end

      def private_url(key, expires_in:, **options)
        linkshare_url(key, expires_in: expires_in, **options)
      end

      def public_url(key, **options)
        linkshare_url(key, expires_in: nil, **options)
      end

      def linkshare_url(key, expires_in:, **options)
        Uplink.parse_access(@access_grant) do |access|
          permission = { allow_download: true, not_after: expires_in.present? ? Time.current + expires_in.to_i : nil }
          prefixes = [ { bucket: @bucket } ]

          access.share(permission, prefixes) do |shared_access|
            edge_credential = shared_access.edge_register_access({ auth_service_address: @auth_service_address }, { is_public: true })
            edge_credential.join_share_url(@link_sharing_address, @bucket, key, { raw: true })
          end
        end
      end

      def custom_metadata_headers(metadata)
        metadata.transform_keys { |key| "x-amz-meta-#{key}" }
      end
  end
end
