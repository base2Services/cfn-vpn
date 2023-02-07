require 'fileutils'
require 'time'
require 'cfnvpn/acm'
require 'cfnvpn/s3'
require 'cfnvpn/log'

module CfnVpn
  class Certificates
    

    def initialize(build_dir, cfnvpn_name, easyrsa_local = false)
      @cfnvpn_name = cfnvpn_name
      @easyrsa_local = easyrsa_local
      
      if @easyrsa_local
        unless which('easyrsa')
          raise "Unable to find `easyrsa` in your path. Check your path or remove the `--easyrsa-local` flag to run from docker"
        end
      end
      
      @build_dir = build_dir
      @config_dir = "#{build_dir}/config"
      @cert_dir = "#{build_dir}/certificates"
      @pki_dir = "#{build_dir}/pki"
      @docker_cmd = %w(docker run -it --rm)
      @easyrsa_image = " base2/aws-client-vpn"
      FileUtils.mkdir_p(@cert_dir)
      FileUtils.mkdir_p(@pki_dir)
    end

    def generate_ca(server_cn,client_cn,expiry=nil)
      opts = ""
      unless expiry.nil?
        opts += "--days=#{expiry}"
      end

      if @easyrsa_local
        ENV["EASYRSA_REQ_CN"] = server_cn
        ENV["EASYRSA_PKI"] = @pki_dir
        system("easyrsa init-pki")
        system("easyrsa build-ca nopass")
        system("easyrsa #{opts} build-server-full server nopass")
        system("easyrsa #{opts} build-client-full #{client_cn} nopass")
        FileUtils.cp(["#{@pki_dir}/ca.crt", "#{@pki_dir}/issued/server.crt", "#{@pki_dir}/private/server.key", "#{@pki_dir}/issued/#{client_cn}.crt", "#{@pki_dir}/private/#{client_cn}.key"], @cert_dir)
        system("tar czfv #{@cert_dir}/ca.tar.gz -C #{@build_dir} pki/")
      else
        @docker_cmd << "-e EASYRSA_REQ_CN=#{server_cn}"
        @docker_cmd << "-e EASYRSA_CLIENT_CN=#{client_cn}"
        @docker_cmd << "-e EASYRSA_OPTS=\"#{opts}\""
        @docker_cmd << "-v #{@cert_dir}:/easy-rsa/output"
        @docker_cmd << @easyrsa_image
        @docker_cmd << "sh -c 'create-ca'"
        CfnVpn::Log.logger.debug `#{@docker_cmd.join(' ')}`
      end
    end

    def generate_client(client_cn,expiry=nil)
      opts = ""
      unless expiry.nil?
        opts += "--days=#{expiry}"
      end

      if @easyrsa_local
        ENV["EASYRSA_PKI"] = @pki_dir
        system("tar xzfv #{@cert_dir}/ca.tar.gz --directory #{@build_dir}")
        system("easyrsa #{opts} build-client-full #{client_cn} nopass")
        system("tar czfv #{@cert_dir}/#{client_cn}.tar.gz -C #{@build_dir} pki/issued/#{client_cn}.crt pki/private/#{client_cn}.key pki/reqs/#{client_cn}.req")
      else
        @docker_cmd << "-e EASYRSA_CLIENT_CN=#{client_cn}"
        @docker_cmd << "-e EASYRSA_OPTS=\"#{opts}\""
        @docker_cmd << "-v #{@cert_dir}:/easy-rsa/output"
        @docker_cmd << @easyrsa_image
        @docker_cmd << "sh -c 'create-client'"
        CfnVpn::Log.logger.debug `#{@docker_cmd.join(' ')}`
      end
    end

    def renew(server_cn,client_cn,expiry=nil)
      opts = ""
      unless expiry.nil?
        opts += "--days=#{expiry}"
      end

      if @easyrsa_local
        ENV["EASYRSA_REQ_CN"] = server_cn
        ENV["EASYRSA_PKI"] = @pki_dir
        system("tar xzfv #{@cert_dir}/ca.tar.gz --directory #{@build_dir}")
        system("easyrsa #{opts} renew server nopass")
        system("easyrsa #{opts} renew #{client_cn} nopass")
        FileUtils.cp(["#{@pki_dir}/ca.crt", "#{@pki_dir}/issued/server.crt", "#{@pki_dir}/private/server.key", "#{@pki_dir}/issued/#{client_cn}.crt", "#{@pki_dir}/private/#{client_cn}.key"], @cert_dir)
        system("tar czfv #{@cert_dir}/ca.tar.gz -C #{@build_dir} pki/")
      else
        @docker_cmd << "-e EASYRSA_REQ_CN=#{server_cn}"
        @docker_cmd << "-e EASYRSA_CLIENT_CN=#{client_cn}"
        @docker_cmd << "-e EASYRSA_OPTS=\"#{opts}\""
        @docker_cmd << "-v #{@cert_dir}:/easy-rsa/output"
        @docker_cmd << @easyrsa_image
        @docker_cmd << "sh -c 'renew'"
        CfnVpn::Log.logger.debug `#{@docker_cmd.join(' ')}`
      end
    end

    def rebuild(server_cn,client_cn,expiry=nil)
      timestamp = Time.now.getutc.to_i
      opts = ""
      unless expiry.nil?
        opts += "--days=#{expiry}"
      end

      if @easyrsa_local
        ENV["EASYRSA_REQ_CN"] = server_cn
        ENV["EASYRSA_PKI"] = @pki_dir
        system("tar xzfv #{@cert_dir}/ca.tar.gz --directory #{@build_dir}")

        FileUtils.mv("#{@pki_dir}/reqs/server.req", "#{@pki_dir}/reqs/server.req.bak-#{timestamp}")
        FileUtils.mv("#{@pki_dir}/issued/server.crt", "#{@pki_dir}/issued/server.req.bak-#{timestamp}")
        FileUtils.mv("#{@pki_dir}/private/server.key", "#{@pki_dir}/private/server.req.bak-#{timestamp}")
        FileUtils.mv("#{@pki_dir}/reqs/#{client_cn}.req", "#{@pki_dir}/reqs/#{client_cn}.req.bak-#{timestamp}")
        FileUtils.mv("#{@pki_dir}/issued/#{client_cn}.crt", "#{@pki_dir}/issued/#{client_cn}.req.bak-#{timestamp}")
        FileUtils.mv("#{@pki_dir}/private/#{client_cn}.key", "#{@pki_dir}/private/#{client_cn}.req.bak-#{timestamp}")

        system("easyrsa #{opts} build-server-full server nopass")
        system("easyrsa #{opts} build-client-full #{client_cn} nopass")
        FileUtils.cp(["#{@pki_dir}/ca.crt", "#{@pki_dir}/issued/server.crt", "#{@pki_dir}/private/server.key", "#{@pki_dir}/issued/#{client_cn}.crt", "#{@pki_dir}/private/#{client_cn}.key"], @cert_dir)
        system("tar czfv #{@cert_dir}/ca.tar.gz -C #{@build_dir} pki/")
      else
        @docker_cmd << "-e EASYRSA_REQ_CN=#{server_cn}"
        @docker_cmd << "-e EASYRSA_CLIENT_CN=#{client_cn}"
        @docker_cmd << "-e EASYRSA_OPTS=\"#{opts}\""
        @docker_cmd << "-v #{@cert_dir}:/easy-rsa/output"
        @docker_cmd << @easyrsa_image
        @docker_cmd << "sh -c 'rebuild'"
        CfnVpn::Log.logger.debug `#{@docker_cmd.join(' ')}`
      end
    end

    def revoke_client(client_cn)
      if @easyrsa_local
        ENV["EASYRSA_PKI"] = @pki_dir
        system("tar xzfv #{@cert_dir}/ca.tar.gz --directory #{@build_dir}")
        system("tar xzfv #{@cert_dir}/#{client_cn}.tar.gz --directory #{@build_dir}")
        system("easyrsa revoke #{client_cn}")
        system("easyrsa gen-crl")
        FileUtils.cp("#{@pki_dir}/crl.pem", @cert_dir)
      else
        @docker_cmd << "-e EASYRSA_CLIENT_CN=#{client_cn}"
        @docker_cmd << "-v #{@cert_dir}:/easy-rsa/output"
        @docker_cmd << @easyrsa_image
        @docker_cmd << "sh -c 'revoke-client'"
        CfnVpn::Log.logger.debug `#{@docker_cmd.join(' ')}`
      end
    end

    def upload_certificates(region,cert,type,cn=nil)
      cn = cn.nil? ? cert : cn
      acm = CfnVpn::Acm.new(region, @cert_dir)
      arn = acm.import_certificate("#{cert}.crt", "#{cert}.key", "ca.crt")
      CfnVpn::Log.logger.debug "Uploaded #{type} certificate to ACM #{arn}"
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
    
    def which(cmd)
      exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
      ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
        exts.each do |ext|
          exe = File.join(path, "#{cmd}#{ext}")
          return exe if File.executable?(exe) && !File.directory?(exe)
        end
      end
      nil
    end

  end
end
