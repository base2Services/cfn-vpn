require 'fileutils'
require 'cfnvpn/acm'
require 'cfnvpn/s3'
require 'cfnvpn/log'

module CfnVpn
  class Certificates
    include CfnVpn::Log

    def initialize(build_dir,cfnvpn_name)
      @cfnvpn_name = cfnvpn_name
      @config_dir = "#{build_dir}/config"
      @cert_dir = "#{build_dir}/certificates"
      @docker_cmd = %w(docker run -it --rm)
      @docker_cmd << "--user #{Process.uid}:#{Process.gid}" if Process::UID.sid_available?
      @easyrsa_image = "base2/aws-client-vpn"
      FileUtils.mkdir_p(@cert_dir)
    end

    def generate_ca(server_cn,client_cn)
      @docker_cmd << "-e EASYRSA_REQ_CN=#{server_cn}"
      @docker_cmd << "-e EASYRSA_CLIENT_CN=#{client_cn}"
      @docker_cmd << "-v #{@cert_dir}:/easy-rsa/output"
      @docker_cmd << @easyrsa_image
      @docker_cmd << "sh -c 'create-ca'"
      return `#{@docker_cmd.join(' ')}`
    end

    def generate_client(client_cn)
      @docker_cmd << "-e EASYRSA_CLIENT_CN=#{client_cn}"
      @docker_cmd << "-v #{@cert_dir}:/easy-rsa/output"
      @docker_cmd << @easyrsa_image
      @docker_cmd << "sh -c 'create-client'"
      return `#{@docker_cmd.join(' ')}`
    end

    def revoke_client(client_cn)
      @docker_cmd << "-e EASYRSA_CLIENT_CN=#{client_cn}"
      @docker_cmd << "-v #{@cert_dir}:/easy-rsa/output"
      @docker_cmd << @easyrsa_image
      @docker_cmd << "sh -c 'revoke-client'"
      return `#{@docker_cmd.join(' ')}`
    end

    def upload_certificates(region,cert,type,cn=nil)
      cn = cn.nil? ? cert : cn
      acm = CfnVpn::Acm.new(region, @cert_dir)
      arn = acm.import_certificate("#{cert}.crt", "#{cert}.key", "ca.crt")
      Log.logger.debug "Uploaded #{type} certificate to ACM #{arn}"
      acm.tag_certificate(arn,cn,type,@cfnvpn_name)
      return arn
    end

    def store_certificate(bucket,bundle)
      s3 = CfnVpn::S3.new(@region,bucket,@name)
      s3.store_object("#{@cert_dir}/#{bundle}")
    end

    def retrieve_certificate(bucket,bundle)
      s3 = CfnVpn::S3.new(@region,bucket,@name)
      s3.get_object("#{@cert_dir}/#{bundle}")
    end

    def extract_certificate(client_cn)
      tar = "#{@config_dir}/#{client_cn}.tar.gz"
      `tar xzfv #{tar} -C #{@config_dir} --strip 2`
      File.delete(tar) if File.exist?(tar)
    end

  end
end
