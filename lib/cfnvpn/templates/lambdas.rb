require 'zip'
require 'securerandom'
require 'aws-sdk-s3'
require 'cfnvpn/log'

module CfnVpn
  module Templates
    class Lambdas

      def self.package_lambda(name:, bucket:, func:, files:)
        lambdas_dir = File.join(File.dirname(File.expand_path(__FILE__)), 'lambdas')
        FileUtils.mkdir_p(lambdas_dir)

        CfnVpn::Log.logger.debug "zipping lambda function #{func}"
        zipfile_name = "#{func}-#{SecureRandom.hex}.zip"
        zipfile_path = "#{CfnVpn.cfnvpn_path}/#{name}/lambdas"
        FileUtils.mkdir_p(zipfile_path)
        Zip::File.open("#{zipfile_path}/#{zipfile_name}", Zip::File::CREATE) do |zipfile|
          files.each do |file|
            zipfile.add(file, File.join("#{lambdas_dir}/#{func}", file))
          end
        end

        bucket = Aws::S3::Bucket.new(bucket)
        object = bucket.object("cfnvpn/lambdas/#{name}/#{zipfile_name}")
        CfnVpn::Log.logger.debug "uploading #{zipfile_name} to s3://#{bucket}/#{object.key}"
        object.upload_file("#{zipfile_path}/#{zipfile_name}")

        return object.key
      end
      
    end
  end
end

