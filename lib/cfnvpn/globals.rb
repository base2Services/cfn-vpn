module CfnVpn
  class << self
    
    # Returns the filepath to the location CfnVpn will use for
    # storage. Used for certificate generation as well as the 
    # download and upload location. Can be overridden by specifying 
    # a value for the ENV variable
    # 'CFNVPN_PATH'.
    #
    # @return [String]
    def cfnvpn_path
      @cfnvpn_path ||= File.expand_path(ENV["CFNVPN_PATH"] || "~/.cfnvpn")
    end
    
  end
end