# frozen_string_literal: true

require "service/shared_service_tests"
require "net/http"

if SERVICE_CONFIGURATIONS[:storj_public]
  class ActiveStorage::Service::StorjPublicServiceTest < ActiveSupport::TestCase
    SERVICE = ActiveStorage::Service.configure(:storj_public, SERVICE_CONFIGURATIONS)

    include ActiveStorage::Service::SharedServiceTests

    test "public URL generation" do
      url = @service.url(@key, filename: ActiveStorage::Filename.new("avatar.png"))

      assert_match(/#{@link_sharing_address}\/raw\/[a-z].*\/#{@service.bucket}\/#{@key}/, url)

      response = Net::HTTP.get_response(URI(url))
      assert_equal "200", response.code
    end
  end
else
  puts "Skipping Storj Public Service tests because no storj_public configuration was supplied"
end
