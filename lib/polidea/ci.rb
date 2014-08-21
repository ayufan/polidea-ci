require 'thor'
require 'travis/yaml'

module Polidea
  module Ci
    class Cli < Thor
      desc 'lint', 'Do verify build process'
      def lint
        parse_yaml
      end

      desc 'variants', 'Print available variants'
      def variants
        parameters = parse_yaml

        if @parameters.branches
          if @parameters.branches.only
            return unless @parameters.branches.only.include? default_build.branch
          elsif @parameters.branches.except
            return if @parameters.branches.except.include? default_build.branch
          end
        end

        Travis::Yaml.matrix(build_config_params).each do |matrix_entry|

        end
      end

      private

      def current_branch
        
      end

      def parse_yaml
        Travis::Yaml.parse!(travis_yaml)
      end

      def travis_yaml
        File.read('.travis.yml')
      end
    end
  end
end
