# lib/terramena.rb
# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'find'
require 'json'
require 'tmpdir'

module Terramena
  VERSION = '0.1.0'

  class << self
    attr_accessor :logger
  end

  # Contains the data related to a NixOS host
  class NixosHost
    # @param args [Hash]
    def initialize(args)
      args.each do |k, v|
        instance_variable_set("@#{k}", v) unless v.nil?
      end

      create_getters
    end

    # @return [String]
    def to_s
      vars = instance_variables.map do |v|
        "#{v.to_s.sub('@', '').capitalize}: #{instance_variable_get(v)}"
      end

      vars.join(', ')
    end

    # @return [String]
    def to_short_s
      tags = if @tags.nil?
               []
             else
               @tags
             end

      "Hostname: #{@hostname} \t tags: #{tags.join(', ')} \t ip: #{@ip}"
    end

    def to_json(*_args)
      hash = {}
      instance_variables.each do |var|
        hash[var.to_s.gsub('@', '')] = instance_variable_get var
      end
      hash.to_json
    end

    # @param input [String]
    def from_json!(input)
      JSON.parse(input).each do |var, val|
        instance_variable_set var, val
      end
    end

    private

    def create_getters
      instance_variables.each do |v|
        define_singleton_method(v.to_s.tr('@', '')) do
          instance_variable_get(v)
        end
      end
    end
  end

  COLEMENA_DEPLOYMENT_FILENAME = './colmena_deployment.nix'
  COLEMENA_FILE_SEARCH_DEPTH = 1
  DEFAULT_CHANNEL_FILENAME = './channels.nix'
  DEFAULT_COLMENA_DEPLOYMENT_FILEPATH = "#{__dir__}/../share/colmena_deployment.nix".freeze
  DEFAULT_HOST_DIRNAME = 'hosts'
  DEFAULT_SSH_CONFIG_FILENAME = './ssh_config'
  # Handles interacting with Colmena, the NixOS deployment tool.
  #
  # List of available options:
  #   channel_filename: A nix channel file
  #   host_dir: The name of the folder that contains all the hosts definitions
  #   ssh_config: Path to an ssh_config file
  #   terraform_state_file: Path to a terraform.tfstate file
  #
  #   Here is an example of a channel file: TODO: Finish example file
  #   let
  #     nixos = builtins.fetchTarball {
  #       url = "https://github.com/nixos/nixpkgs/archive/81a3237b64e67b66901c735654017e75f0c50943.tar.gz";
  #       sha256 = "0zvslhjjhphq6cpfvyk72bgkbwhc0kg0r7njnx4fbk73wfj6cg3z";
  #     };
  #     nixos-unstable = builtins.fetchTarball {
  #       url = "https://github.com/nixos/nixpkgs/archive/854fdc68881791812eddd33b2fed94b954979a8e.tar.gz";
  #       sha256 = "0wxncmb390dl3rzfpfpzy7fb0jpdi6gx6y8m85vl4abqcrjzvwds";
  #     };
  #   in
  #   {
  #     pkgs = import nixos { };
  #     unstable = import nixos-unstable { };
  #   }
  class Colmena
    # @param module_root [String] "Fullpath to the nixos module root (files used by colmena)"
    # @param tags [String] "List of tags passed to Colemena"
    def initialize(module_root, tags = [], extra_paths = [], options = {})
      @module_root = module_root
      @tags = tags
      @extra_paths = extra_paths
      @logger = Terramena.logger

      options[:ssh_config] = DEFAULT_SSH_CONFIG_FILENAME if options[:ssh_config].nil?
      @ssh_config_filename = options[:ssh_config]

      options[:channel_filename] = DEFAULT_CHANNEL_FILENAME if options[:channel_filename].nil?
      @channel_filename = options[:channel_filename]

      options[:terraform_state_file] = DEFAULT_TERRAFORM_STATE_FILE if options[:terraform_state_file].nil?
      @terraform_state_file = options[:terraform_state_file]

      options[:host_dir] = DEFAULT_HOST_DIRNAME if options[:host_dir].nil?
      @host_dir = options[:host_dir]

      # modified during runtime
      @temp_dir = ''
      @deployment_file = ''
    end

    def list
      terraform = Terramena::Terraform.new(@terraform_state_file)
      nixos_hosts = terraform.nixos_hosts(@tags)
      print_hosts(nixos_hosts, use_logger: false)
    end

    def deploy(goal = 'apply', show_trace: false, no_substitutes: false)
      build_module_root_dir
      colemana_deployment_file
      run_colmena(goal, show_trace:, no_substitutes:)
    end

    def cleanup
      FileUtils.rm_rf @temp_dir unless @temp_dir.empty?
    end

    private

    def run_colmena(goal = 'apply', show_trace: false, no_substitutes: false)
      cmd = colmena_command(goal, show_trace:, no_substitutes:)
      @logger.debug "colmena env: #{colmena_env}"
      @logger.debug "colmena command: #{cmd}"

      pid = spawn(colmena_env, cmd)

      Signal.trap('TERM', pid) do
        Process.kill('TERM', pid)
      end

      Process.wait
    end

    def colmena_command(goal, show_trace: false, no_substitutes: false)
      <<~COLMENA_CMD
        colmena #{goal}#{' --no-substitutes' if no_substitutes} \
                -f #{@deployment_file}#{tags_for_colmena_command}#{' --show-trace' if show_trace}
      COLMENA_CMD
    end

    def print_hosts(nixos_hosts, use_logger: true)
      lines = [
        "Found #{nixos_hosts.length} host#{'s' if nixos_hosts.length > 1}"
      ]

      nixos_hosts.each { |host| lines.push host.to_short_s }

      lines.each do |line|
        if use_logger
          @logger.info line
        else
          puts line
        end
      end
    end

    def build_colmena_deployment_filepath(depth = COLEMENA_FILE_SEARCH_DEPTH)
      f = File.realpath(DEFAULT_COLMENA_DEPLOYMENT_FILEPATH)
      if File.exist? f
        f
      else
        @logger.debug 'colmena deployment file not found in standard location, trying to find it...'

        find_colmena_deployment_filepath!(depth)
      end
    end

    def find_colmena_deployment_filepath!(depth)
      # Try to search for the file by going backwards with a maxixum depth
      path = "#{__dir__}/"
      depth.times { |_i| path += '../' }

      Find.find(path) do |p|
        p if File.basename == COLEMENA_DEPLOYMENT_FILENAME
      end

      raise StandardError("colmena deployment file named #{COLMENA_DEPLOYMENT_FILENAME} not found")
    end

    def build_module_root_dir
      @logger.info 'building temporary directory'
      @temp_dir = Dir.mktmpdir('terramena')
      @logger.debug "using temporary directory named #{@temp_dir}"

      @logger.debug "copying files from NixOS root dir #{@module_root}"
      FileUtils.cp_r("#{@module_root}/.", @temp_dir)
      @logger.debug 'files copied'

      @logger.debug 'copying the channel file'
      FileUtils.cp @channel_filename, @temp_dir
      @logger.debug 'channel file copied'

      @logger.debug 'copy the colmena deployment file'
      FileUtils.cp build_colmena_deployment_filepath, @temp_dir
      @logger.debug 'deployment file copied'

      @logger.debug 'copying extra paths to the temp dir'
      @extra_paths.each { |path| FileUtils.cp_r path, "#{@temp_dir}/" }
    end

    def colemana_deployment_file
      @logger.debug "using Terraform state file #{@terraform_state_file}"
      terramena = Terramena::Terraform.new(@terraform_state_file)
      nixos_hosts = terramena.nixos_hosts(@tags)
      print_hosts(nixos_hosts)

      colmena_filename = File.realpath File.join(@temp_dir, COLEMENA_DEPLOYMENT_FILENAME)
      channel_filename = File.realpath File.join(@temp_dir, File.basename(@channel_filename))

      @logger.info 'building colmena deployment file...'
      cmd = <<~NIX_BUILD_CMD
        nix-build "#{colmena_filename}" \
            --no-out-link \
            --argstr hosts '#{nixos_hosts.to_json}' \
            --argstr channels "#{channel_filename}"
      NIX_BUILD_CMD

      @logger.debug "running nix_build_command: #{cmd}"
      @deployment_file = `#{cmd}`.strip
      @logger.fatal 'Failed to run nix-build' if $CHILD_STATUS != 0

      @logger.debug "using deployment file #{@deployment_file}"
    end

    def colmena_env
      env = {}
      env['SSH_CONFIG_FILE'] = @ssh_config_filename if File.exist? @ssh_config_filename
      env
    end

    def tags_for_colmena_command
      tags_command = ''

      unless @tags.empty?
        colmena_tags = @tags.map { |t| "@#{t}" }
        tags_command = " --on #{colmena_tags.join(',')}"
      end

      tags_command
    end
  end

  DEFAULT_TERRAFORM_STATE_FILE = './terraform.tfstate'
  # Handles working with terraform output to find different values
  class Terraform
    def initialize(state_filename)
      @state_filename = state_filename
    end

    # Returns a list of NixOS hosts gathered from Terraform's output
    # TODO: refactor to reduce complexity
    def nixos_hosts(tags = [])
      begin
        terraform_values = JSON.parse(File.read(@state_filename))['outputs']
      rescue StandardError => e
        warn "failed to read state file #{@state_filename}: #{e}"
        exit 1
      end

      hash_hosts = find_nixos_hosts(terraform_values)
      unless tags.empty?
        hash_hosts = hash_hosts.select do |host|
          has_tag = false

          tags.each do |tag|
            has_tag = true if host['tags'].include? tag
          end

          has_tag
        end
      end

      hash_hosts.map { |h| NixosHost.new(h) }
    end

    private

    # Go through the terraform output and find hashes that have a key-value pair of
    # '_type' => 'nixos_host'
    def find_nixos_hosts(node)
      hosts = []

      case node
      when Hash
        node.each do |k, v|
          # Try to find a key named _type
          hosts.append(node) if (k == '_type') && (v == 'nixos_host')

          hosts += find_nixos_hosts(v)
        end
      when Array
        node.each { |o| hosts += find_nixos_hosts(o) }
      end

      hosts
    end
  end
end
