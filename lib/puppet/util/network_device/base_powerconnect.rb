require 'uri'
require 'openssl'
require 'cgi'
require 'puppet/util/network_device/transport_powerconnect'
require 'puppet/util/network_device/transport_powerconnect/base_powerconnect'
require '/etc/puppetlabs/puppet/modules/asm_lib/lib/security/encode'


# Base class which provides transport initialization
# based on the information provided in device.conf file
#
class Puppet::Util::NetworkDevice::Base_powerconnect
  attr_accessor :url, :transport, :crypt
  def initialize(url)
    @url = URI.parse(url)
    @query = Hash.new([])
    @query = CGI.parse(@url.query) if @url.query

    require "puppet/util/network_device/transport_powerconnect/#{@url.scheme}"

    unless @transport
      @transport = Puppet::Util::NetworkDevice::Transport_powerconnect.const_get(@url.scheme.capitalize).new
      @transport.host = @url.host
      @transport.port = case @url.scheme ; when "ssh" ; 22 ; when "telnet" ; 23 ; else "Invalid protocol" end || @url.port
      if @query && @query['crypt'] && @query['crypt'] == ['true']
        self.crypt = true
        # FIXME: https://github.com/puppetlabs/puppet/blob/master/lib/puppet/application/device.rb#L181
        master = File.read(File.join('/etc/puppet', 'networkdevice-secret'))
        master = master.strip
        @transport.user = decrypt(master, [@url.user].pack('h*'))
        @transport.password = decrypt(master, [@url.password].pack('h*'))
      else
        @transport.user = URI.decode(@url.user)
        @transport.password = URI.decode(asm_decrypt(@url.password))
      end
    end

    override_using_credential_id
  end

  def override_using_credential_id
    if id = @query.fetch('credential_id', []).first
      require 'asm/cipher'
      cred = ASM::Cipher.decrypt_credential(id)
      @transport.user = cred.username
      @transport.password = cred.password
    end
  end

  def decrypt(master, str)
    cipher = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
    cipher.decrypt
    cipher.key = key = OpenSSL::Digest::SHA512.new(master).digest
    out = cipher.update(str)
    out << cipher.final
    return out
  end
end
