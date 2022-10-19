# lib/commands.rb

require 'logger'
require 'slop'
require_relative './terramena'

module Slop
  class PathOption < Option
    def call(path); end
  end
end

module Commands
  VERSION = '0.0.1'

  class << self
    attr_accessor :logger
  end

  class ExitError < StandardError
  end

  class Command
    # @return [void]
    def initialize(opts, args)
      begin
        opts.bool '--debug', 'print debugging information'
        parser = Slop::Parser.new(opts)
        @args = args

        @result = parser.parse(args)
      rescue Slop::MissingRequiredOption => e
        puts e
        puts opts
        raise Commands::ExitError
      end

      @opts = opts
      setup_logger
    end

    private

    def setup_logger
      logger = Logger.new($stdout)
      logger.formatter = proc do |severity, _datetime, _progname, msg|
        "[#{severity}]: #{msg}\n"
      end
      logger.level = if @result.debug?
                       Logger::DEBUG
                     else
                       Logger::WARN
                     end

      # Set the logger for each module used
      @logger = logger
      Terramena.logger = logger
    end
  end

  class List < Command
    def initialize(args)
      opts = Slop::Options.new
      opts.array '-t', '--tags', 'tags to deploy with colmena (seperated by a comma)'
      opts.string '-s', '--state', 'fullpath to the terraform state file',
                  default: Terramena::DEFAULT_TERRAFORM_STATE_PATH

      super(opts, args)
    end

    def run
      t = Terramena::Colmena.new '', @result[:tags]
      t.list @result[:state]
    end
  end

  class Ssh < Command
    def initialize(args)
      opts = Slop::Options.new
      opts.string '-u', '--user', 'username to use for SSH, can be used also through username@host'
      opts.string '-i', '--keyfile', 'key file to use during connection'
      opts.string '-s', '--state', 'fullpath to the terraform state file',
                  default: Terramena::DEFAULT_TERRAFORM_STATE_PATH
      opts.string '-c', '--sshconfig', 'fullpath to the ssh_config file',
                  default: Terramena::DEFAULT_SSH_CONFIG_FILENAME
      opts.bool '-v', '--verbose', 'make ssh talk more'

      super(opts, args)
    end

    def run
      @result.arguments.shift # removes the command (ssh)
      parse_arguments

      terramena = Terramena::Terraform.new(@result[:state])
      nixos_hosts = terramena.nixos_hosts()

      # Check if the hostname matches any hosts in the found nixos_hosts
      nixos_hosts.each do |host|
        next unless host.hostname == @hostname

        connect_to_host(host)
      end

      warn "cannot find hostname #{@hostname} in nixos hosts"
      exit 1
    end

    private

    # @param host [Hash] "Terraform output hash for a host"
    def connect_to_host(host)
      @logger.debug "ssh_switches: #{ssh_switches}"

      target = "#{@username}@#{host.ip}"
      target = host.ip if @username.nil?
      @logger.debug "target: #{target}"

      cmd = "ssh #{ssh_switches.join(' ')} #{target}"

      @logger.debug "ssh command: #{cmd}"
      exec(cmd)
    end

    def ssh_switches
      ssh_switches = []

      ssh_switches += ['-F', @result[:sshconfig]] if !@result[:sshconfig].nil? && (File.exist? @result[:sshconfig])
      ssh_switches += ['-i', @result[:keyfile]] if !@result[:keyfile].nil? && (File.exist? @result[:keyfile])
      ssh_switches += ['-v'] if !@result[:verbose].nil? && (@result.key? :verbose)
      ssh_switches
    end

    def parse_arguments
      raise Slop::MissingRequiredOption, 'a hostname is required as the first argument' if @result.arguments.empty?

      @hostname = @result.arguments.shift
      @username = @result['username']
      @username, @hostname = @hostname.split('@') if @hostname.include? '@'
      @logger.debug "hostname: '#{@hostname}'"
      @logger.debug "username: '#{@username}'"
    end
  end

  class Deploy < Command
    def initialize(args)
      opts = Slop::Options.new
      opts.array '-t', '--tags', 'tags to deploy with colmena (seperated by a comma)'
      opts.string '-s', '--state', 'fullpath to the terraform state file',
                  default: Terramena::DEFAULT_TERRAFORM_STATE_PATH
      opts.string '-c', '--sshconfig', 'fullpath to the ssh_config file',
                  default: Terramena::DEFAULT_SSH_CONFIG_FILENAME
      opts.string '-m', '--module', 'path to the nixos module root', required: true
      opts.string '-x', '--channel', 'path to the channel file to use', default: Terramena::DEFAULT_CHANNEL_FILENAME
      opts.array '-p', '--paths', 'list of extra paths to copy to the module_root (seperated by a comma)'
      opts.bool '--no-substitutes', 'do not use subsitution (nixos binary caches) when pushing the new configuration'
      opts.bool '--show-trace', 'show trace during nix builds'

      super(opts, args)
    end

    def run
      set_options
      @logger.debug(@result.to_hash)

      begin
        colmena = Terramena::Colmena.new(@module_path, @tags, @extra_paths,
                                         options = { terraform_state_path: @terraform_state,
                                                     ssh_config: @ssh_config,
                                                     channel_filename: @channel_filename })
        colmena.deploy('apply', show_trace: @show_trace, no_substitutes: @no_substitutes)
      ensure
        colmena.cleanup
      end
    end

    private

    def set_options
      # Check if the current path contains a file named ssh_config
      if File.exist? @result[:sshconfig]
        # If it does, use it
        @ssh_config = File.realpath @result[:sshconfig]
      else
        @ssh_config = ''
        warn 'warning: no ssh_config file provided'
      end

      # Channel file is required, if it's not found we error out
      if File.exist? @result[:channel]
        @channel_filename = File.realpath @result[:channel]
      else
        raise Slop::MissingRequiredOption, "invalid channel file #{@result[:channel]} provided"
      end

      # Make sure the module folder given exists
      unless File.directory? @result[:module]
        raise Slop::MissingRequiredOption, "invalid nixos root module directory, #{@result[:module]} provided"
      end

      # The terraform state needs to be an existing file
      unless File.exist? @result[:state]
        raise Slop::MissingRequiredOption, "invalid terrform state file, #{@result[:state]} provided"
      end

      @module_path = File.realdirpath @result[:module]
      @tags = @result[:tags]
      @extra_paths = @result[:paths]
      @state = @result[:state]
      @show_trace = @result.show_trace?
      @no_substitutes = @result.no_substitutes?
    end
  end
end
