require 'aws-sdk-s3'
require 'fileutils'
require 'securerandom'

module CfnVpn
  class S3Bucket

    def initialize(region, name)
      @client = Aws::S3::Client.new(region: region)
      @name = name
    end

    def generate_bucket_name
      return "cfnvpn-#{@name}-#{SecureRandom.hex}"
    end

    def create_bucket(bucket)
      @client.create_bucket({
        bucket: bucket,
        acl: 'private'
      })

      @client.put_public_access_block({
        bucket: bucket,
        public_access_block_configuration: { 
          block_public_acls: true,
          ignore_public_acls: true,
          block_public_policy: true,
          restrict_public_buckets: true,
        }
      })

      @client.put_bucket_encryption({
        bucket: bucket,
        server_side_encryption_configuration: {
          rules: [
            {
              apply_server_side_encryption_by_default: {
                sse_algorithm: "AES256"
              }
            }
          ]
        }
      })
    end

  end
end
