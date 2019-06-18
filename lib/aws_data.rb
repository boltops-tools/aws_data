require "aws_data/version"
require "aws-sdk-core"
require "aws-sdk-sts"
require "memoist"

class AwsData
  class Error < StandardError; end
  extend Memoist

  def region
    return 'us-east-1' if test?

    return ENV['AWS_REGION'] if ENV['AWS_REGION'] # highest precedence

    region = nil

    # First if aws binary is available
    # try to get it from the ~/.aws/config
    if which('aws')
      region = `aws configure get region 2>&1`.strip rescue nil
      exit_code = $?.exitstatus
      if exit_code != 0
        exception_message = region.split("\n").grep(/botocore\.exceptions/).first
        if exception_message
          puts "WARN: #{exception_message}".color(:yellow)
        else
          # show full message as warning
          puts region.color(:yellow)
        end
        puts "You can also get rid of this message by setting AWS_REGION or configuring ~/.aws/config with the region"
        region = nil
      end
      region = nil if region == ''
      return region if region
    end

    # Second try the metadata endpoint, should be available on AWS Lambda environment
    # https://stackoverflow.com/questions/4249488/find-region-from-within-an-ec2-instance
    begin
      az = `curl -s --max-time 3 --connect-timeout 5 http://169.254.169.254/latest/meta-data/placement/availability-zone`
      region = az.strip.chop # remove last char
      region = nil if region == ''
    rescue
    end
    return region if region

    'us-east-1' # default if all else fails
  end
  memoize :region

  # aws sts get-caller-identity
  def account
    return '123456789' if test?
    # ensure region set, required for sts.get_caller_identity.account to work
    ENV['AWS_REGION'] ||= region
    begin
      sts.get_caller_identity.account
    rescue Aws::Errors::MissingCredentialsError
      puts "INFO: You're missing AWS credentials. Only local services are currently available"
    end
  end
  memoize :account

private
  def test?
    ENV['TEST']
  end

  # Cross-platform way of finding an executable in the $PATH.
  #
  #   which('ruby') #=> /usr/bin/ruby
  #
  # source: https://stackoverflow.com/questions/2108727/which-in-ruby-checking-if-program-exists-in-path-from-ruby
  def which(cmd)
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      exts.each { |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      }
    end
    return nil
  end

  def sts
    Aws::STS::Client.new
  end
  memoize :sts
end
