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
  class << self
    attr_accessor :logger
  end

  class ExitError < StandardError
  end

  class Command
    attr_reader :args

    # @return [void]
    def initialize(opts, args)
      begin
        opts.separator ''
        opts.separator 'common options:'
        opts.bool '--debug', 'print debugging information'
        opts.on '-h', '--help', 'print this help' do
          puts opts
          raise ExitError
        end
        opts.on '-V', '--version', 'print version' do
          puts Terramena::VERSION
          raise ExitError
        end

        parser = Slop::Parser.new(opts)
        @args = parser.parse(args)
      rescue Slop::MissingRequiredOption => e
        puts e
        puts opts
        raise ExitError
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
      logger.level = if @args.debug?
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
                  default: Terramena::DEFAULT_TERRAFORM_STATE_FILE

      super(opts, args)
    end

    def run
      t = Terramena::Colmena.new '', @args[:tags]
      t.list
    end
  end

  class Ssh < Command
    def initialize(args)
      opts = Slop::Options.new
      opts.string '-u', '--user', 'username to use for SSH, can be used also through username@host'
      opts.string '-i', '--keyfile', 'key file to use during connection'
      opts.string '-s', '--state', 'fullpath to the terraform state file',
                  default: Terramena::DEFAULT_TERRAFORM_STATE_FILE
      opts.string '-c', '--sshconfig', 'fullpath to the ssh_config file',
                  default: Terramena::DEFAULT_SSH_CONFIG_FILENAME
      opts.bool '-v', '--verbose', 'make ssh talk more'

      super(opts, args)
    end

    def run
      @args.arguments.shift # removes the command (ssh)
      parse_arguments

      terramena = Terramena::Terraform.new(@args[:state])
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

      ssh_switches += ['-F', @args[:sshconfig]] if !@args[:sshconfig].nil? && (File.exist? @args[:sshconfig])
      ssh_switches += ['-i', @args[:keyfile]] if !@args[:keyfile].nil? && (File.exist? @args[:keyfile])
      ssh_switches += ['-v'] if !@args[:verbose].nil? && (@args.key? :verbose)
      ssh_switches
    end

    def parse_arguments
      raise Slop::MissingRequiredOption, 'a hostname is required as the first argument' if @args.arguments.empty?

      @hostname = @args.arguments.shift
      @username = @args['username']
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
                  default: Terramena::DEFAULT_TERRAFORM_STATE_FILE
      opts.string '-c', '--sshconfig', 'fullpath to the ssh_config file',
                  default: Terramena::DEFAULT_SSH_CONFIG_FILENAME
      opts.string '-m', '--module', 'path to the nixos module root', required: true
      opts.string '-x', '--channel', 'path to the channel file to use', default: Terramena::DEFAULT_CHANNEL_FILENAME
      opts.array '-p', '--paths', 'list of extra paths to copy to the module_root (seperated by a comma)',
                 delimiter: ','
      opts.bool '--no-substitutes', 'do not use subsitution (nixos binary caches) when pushing the new configuration'
      opts.bool '--show-trace', 'show trace during nix builds'

      super(opts, args)
    end

    def run
      set_options
      @logger.debug "options passed: #{@args.to_hash}"

      begin
        colmena = Terramena::Colmena.new(@args[:module], @args[:tags], @args[:paths],
                                         options = { terraform_state_file: @args[:state],
                                                     ssh_config: @args[:sshconfig],
                                                     channel_filename: @args[:channel] })
        colmena.deploy('apply', show_trace: @args[:show_trace], no_substitutes: @args[:no_substitutes])
      ensure
        colmena.cleanup
      end
    end

    private

    def set_options
      # Check if the current path contains a file named ssh_config
      if File.exist? @args[:sshconfig]
        # If it does, use it
        @ssh_config = File.realpath @args[:sshconfig]
      else
        @ssh_config = ''
        warn 'warning: no ssh_config file provided'
      end

      # Channel file is required, if it's not found we error out
      unless File.exist? @args[:channel]
        raise Slop::MissingRequiredOption,
              "invalid channel file #{@args[:channel]} provided"
      end

      @channel_filename = File.realpath @args[:channel]

      # Make sure the module folder given exists
      unless File.directory? @args[:module]
        raise Slop::MissingRequiredOption, "invalid nixos root module directory, #{@args[:module]} provided"
      end

      # The terraform state needs to be an existing file
      unless File.exist? @args[:state]
        raise Slop::MissingRequiredOption, "invalid terrform state file, #{@args[:state]} provided"
      end

      @module_path = File.realdirpath @args[:module]
      @tags = @args[:tags]
      @extra_paths = @args[:paths]
      @state = @args[:state]
      @show_trace = @args['show-trace']
      @no_substitutes = @args['no-substitutes']
    end
  end
end
