require 'fileutils'
require 'cfnvpn/acm'

module CfnVpn
  class Certificates

    def initialize(build_dir)
      @cert_dir = "#{build_dir}/certificates"
      FileUtils.mkdir_p(@cert_dir)
    end

    def generate(server_cn,client_cn)
      cmd = ["docker", "run", "-it", "--rm"]
      cmd << "-e EASYRSA_REQ_CN=#{server_cn}"
      cmd << "-e EASYRSA_CLIENT_CN=#{client_cn}"
      cmd << "-v #{@cert_dir}:/easy-rsa/output"
      cmd << "base2/aws-client-vpn"
      return `#{cmd.join(' ')}`
    end

    def upload_certificates(region,cert,type,cfnvpn_name,cn=nil)
      cn = cn.nil? ? cert : cn
      acm = CfnVpn::Acm.new(region, @cert_dir)
      arn = acm.import_certificate("#{cert}.crt", "#{cert}.key", "ca.crt")
      acm.tag_certificate(arn,cn,type,cfnvpn_name)
      return arn
    end

    def command?(name)
      [name,
       *ENV['PATH'].split(File::PATH_SEPARATOR).map {|p| File.join(p, name)}
      ].find {|f| File.executable?(f)}
    end

  end
end
