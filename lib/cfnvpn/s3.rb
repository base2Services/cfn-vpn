require 'aws-sdk-s3'
require 'fileutils'

module CfnVpn
  class S3

    def initialize(region, bucket, name)
      @client = Aws::S3::Client.new(region: region)
      @bucket = bucket
      @name = name
      @path = "cfnvpn/certificates/#{@name}"
    end

    def store_object(file)
      body = File.open(file, 'rb').read
      file_name = file.split('/').last
      CfnVpn::Log.logger.debug("uploading #{file} to s3://#{@bucket}/#{@path}/#{file_name}")
      @client.put_object({
        body: body,
        bucket: @bucket,
        key: "#{@path}/#{file_name}",
        server_side_encryption: "AES256",
        tagging: "cfnvpn:name=#{@name}"
      })
    end

    def get_object(file)
      file_name = file.split('/').last
      CfnVpn::Log.logger.debug("downloading s3://#{@bucket}/#{@path}/#{file_name} to #{file}")
      @client.get_object(
        response_target: file,
        bucket: @bucket,
        key: "#{@path}/#{file_name}")
    end

    def store_config(config)
      CfnVpn::Log.logger.debug("uploading config to s3://#{@bucket}/#{@path}/#{@name}.config.ovpn")
      @client.put_object({
        body: config,
        bucket: @bucket,
        key: "#{@path}/#{@name}.config.ovpn",
        tagging: "cfnvpn:name=#{@name}"
      })
    end

    def get_url(file)
      presigner = Aws::S3::Presigner.new(client: @client)
      params = {
        bucket: @bucket,
        key: "#{@path}/#{file}",
        expires_in: 3600
      }
      presigner.presigned_url(:get_object, params)
    end

    def store_embedded_config(config, cn)
      CfnVpn::Log.logger.debug("uploading config to s3://#{@bucket}/#{@path}/#{@name}_#{cn}.config.ovpn")
      @client.put_object({
        body: config,
        bucket: @bucket,
        key: "#{@path}/#{@name}_#{cn}.config.ovpn",
        tagging: "cfnvpn:name=#{@name}"
      })
    end

  end
end
