require 'aws-sdk-ec2'

module CfnVpn
  module Templates
    class Helper
      def self.get_auth_cidr(region, subnet_id)
        client = Aws::EC2::Client.new(region: region)
        subnets = client.describe_subnets({subnet_ids:[subnet_id]})
        vpcs = client.describe_vpcs({vpc_ids:[subnets.subnets[0].vpc_id]})
        return vpcs.vpcs[0].cidr_block
      end
    end
  end
end