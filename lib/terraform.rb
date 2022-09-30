# typed: false
# lib/terraform.rb
# frozen_string_literal: true

require 'json'

module Terramethod
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
      "Hostname: #{@hostname}, tags: #{@tags.join(', ')}, ip: #{@ip}"
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

  # Handles working with terraform output to find different values
  class Terraform
    def initialize(state_filename)
      @state_filename = state_filename
    end

    # Returns a list of NixOS hosts gathered from terraform's output
    def nixos_hosts
      # Go through all the terraform outputs and add their values together
      terraform_values = []
      JSON.parse(`terraform output -state=#{@state_filename} -json`).each do |_key, output_name|
        output_name.each { |k, v| terraform_values.append v if k == 'value' }
      end

      hash_hosts = find_nixos_hosts(terraform_values).map do |host|
        host.reject { |key, _value| key == '_type' }
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
