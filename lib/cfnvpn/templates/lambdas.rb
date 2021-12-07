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
            file_path = lambdas_dir
            
            # this is to allow for shared library methods in a different lambda directory
            # so the files in the function lambda is in the root of the zip
            if file.include? func
              file_path = "#{file_path}/#{func}"
              file.gsub!("#{func}/", "")
            end

            zipfile.add(file, File.join(file_path, file))
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

