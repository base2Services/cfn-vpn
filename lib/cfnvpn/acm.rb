require 'aws-sdk-acm'
require 'fileutils'

module CfnVpn
  class Acm

    def initialize(region,cert_dir)
      @client = Aws::ACM::Client.new(region: region)
      @cert_dir = cert_dir
    end

    def import_certificate(cert,key,ca)
      cert_body = load_certificate(cert)
      key_body = load_certificate(key)
      ca_body = load_certificate(ca)

      resp = @client.import_certificate({
        certificate: cert_body,
        private_key: key_body,
        certificate_chain: ca_body
      })
      return resp.certificate_arn
    end

    def tag_certificate(arn,name,type,cfnvpn_name)
      tags = [
        { key: "Name", value: name },
        { key: "cfnvpn:name", value: cfnvpn_name },
        { key: "cfnvpn:certificate:type", value: type }
      ]

      @client.add_tags_to_certificate({
        certificate_arn: arn,
        tags: tags
      })
    end

    def load_certificate(cert)
      File.read("#{@cert_dir}/#{cert}")
    end

    def get_certificate_tags(certificate_arn,key=nil)
      resp = @client.list_tags_for_certificate({
        certificate_arn: certificate_arn
      })

      if key.nil?
        return resp.tags
      else
        resp.tags.each do |tag|
          return tag.value if tag.key == key
        end

        raise "no tag key #{key} matched the certificate #{certificate_arn}"
      end
    end
  end
end
