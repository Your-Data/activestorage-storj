# ActiveStorage-Storj
ActiveStorage-Storj is a ruby gem that provides [Storj](https://www.storj.io/) cloud storage support for [ActiveStorage](https://guides.rubyonrails.org/active_storage_overview.html) in [Rails](https://rubyonrails.org/).

Note: [direct upload](https://guides.rubyonrails.org/active_storage_overview.html#direct-uploads) is not supported in this gem. To enable direct upload support, install [activestorage-storj-s3](https://github.com/Your-Data/activestorage-storj-s3) gem.

## Requirements
* [Rails v6+](https://guides.rubyonrails.org/getting_started.html)
* Install Active Storage on a Rails project.

    ```bash
    $ bin/rails active_storage:install
    $ bin/rails db:migrate
    ```
* Build and install [uplink-c](https://github.com/storj/uplink-c) library. Follow the guide at [Prerequisites](https://github.com/storj-thirdparty/uplink-ruby#prerequisites) section.

## Installation
* Add this line to your Rails application's Gemfile:

    ```ruby
    gem 'activestorage-storj', '~> 1.0'
    ```

    And then execute:
    ```bash
    $ bundle install
    ```

* Declare a Storj Cloud Storage service in `config/storage.yml`:

    ```yaml
    storj:
      service: storj
      access_grant: ""
      bucket: ""
      auth_service_address: auth.storjshare.io:7777
      link_sharing_address: https://link.storjshare.io
    ```

    Optionally provide upload and download options:

    ```yaml
    storj:
      service: storj
      ...
      upload_chunk_size: 0
      download_chunk_size: 0
    ```

    Add `public: true` to prevent the generated URL from expiring. By default, the private generated URL will expire in 5 minutes.

    ```yaml
    storj:
      service: storj
      ...
      public: true
    ```

## Running the Tests

* Create `configurations.yml` file in `test/dummy/config/environments/service` folder, or copy the existing `configurations.example.yml` as `configurations.yml`.

* Provide Storj configurations for both `storj` and `storj_public` services in `configurations.yml`:

    ```yaml
    storj:
      service: storj
      access_grant: ""
      bucket: ""
      auth_service_address: auth.storjshare.io:7777
      link_sharing_address: https://link.storjshare.io

    storj_public:
      service: storj
      access_grant: ""
      bucket: ""
      auth_service_address: auth.storjshare.io:7777
      link_sharing_address: https://link.storjshare.io
      public: true
    ```

* Run the tests:

    ```bash
    $ bin/test
    ```
