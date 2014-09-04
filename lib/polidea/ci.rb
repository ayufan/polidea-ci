require 'thor'
require 'childprocess'
require 'tempfile'
require 'travis/yaml'
require 'travis/build'
require 'digest/sha1'
require 'core_ext/hash/deep_symbolize_keys'
require 'core_ext/hash/deep_merge'

module Polidea
  module Ci
    class Cli < Thor
      def initialize(*args)
        super

        # redefine some methods
        Travis::Build::Script.send(:define_method, :checkout) do
          cd dir
          sh.to_s
        end
      end

      class_option :file, :aliases => :f, :type => :string, :default => '.travis.yml'
      class_option :branch, :aliases => :b, :type => :string, :banner => 'BRANCH'

      desc 'lint', 'Do verify build process'
      def lint
        parameters
      end

      desc 'variants', 'Print available variants'
      def variants
        fail('branch constraint not met') unless check_branch_constraint

        puts('Build variants:')
        matrix_entries.each do |matrix_entry|
          puts("#{matrix_entries.index(matrix_entry)}\t#{matrix_key(matrix_entry)}\t#{matrix_attributes(matrix_entry)}")
        end
      end

      desc 'config [VARIANT]', 'Show config for variant'
      def config(variant)
        fail('branch constraint not met') unless check_branch_constraint

        matrix_entry = find_matrix_build_by_key(variant)

        puts(matrix_build_config(matrix_entry).to_yaml)
      end

      desc 'build [VARIANT...]', 'Build specific variant'
      option :print, :aliases => :p, :type => :boolean, :default => false
      option :version, :aliases => :V, :type => :string, :banner => '1.0.0rc1', :default => '0.0'
      option :build_number, :aliases => :N, :type => :numeric, :banner => 'BUILD_NUMBER', :default => '1'
      option :tag, :aliases => :T, :type => :string, :banner => 'TAG', :default => 'project_tag'
      def build(*variants)
        fail('branch constraint not met') unless check_branch_constraint

        if variants.include? 'all'
          variants = matrix_entries.map do |matrix_entry|
            matrix_key(matrix_entry)
          end
        end

        variants.each do |variant|
          matrix_entry = find_matrix_build_by_key(variant)
          build_config = matrix_build_config(matrix_entry)
          script = build_script(build_config)
          if options[:p]
            puts(script)
          else
            execute_build(build_config, script)
          end
        end
      end

      private

      def execute_build(build_config, script)
        run_file = Tempfile.new('executor')
        run_file.chmod(0700)
        run_file.puts(script)
        run_file.close

        cmd = "#{runner_script} #{run_file.path}"

        env = {}
        env['CI_OS'] = build_config['os']
        env['CI_LANGUAGE'] = build_config['language']
        env['CI_REPO_SLUG'] = remote_slug.shellescape

        if system(env, 'bash', '--login', '-c', cmd)
          puts('Build finished!')
        else
          puts('Build failed!')
        end
      rescue => e
        run_file.unlink if run_file
        throw e
      end

      def fail(*opts)
        puts(*opts)
        exit(1)
      end

      def find_matrix_build_by_key(key)
        matrix_entries.each do |matrix_entry|
          return matrix_entry if matrix_entries.index(matrix_entry).to_s == key
          return matrix_entry if matrix_key(matrix_entry) == key
        end
        fail("#{key}: no variant found")
      end

      def build_script(build_config)
        data = travis_config(build_config)
        data = data.deep_merge(ci_config[:travis_build]) if ci_config[:travis_build]

        script = Travis::Build.script(data, logs: {build: true, state: false})
        script.compile
      end

      def travis_config(build_config)
        {
            urls: {
            },
            ssh_key: {
                value: ssh_key
            },
            repository: {
                source_url: remote_origin,
                slug: remote_slug
            },
            source: {
                id: current_build_number,
                number: options[:version]
            },
            job: {
                id: 1,
                number: current_build_number,
                branch: current_branch,
                commit: current_commit,
                commit_range: "before_commit..#{current_commit}",
                pull_request: false,
                tag: options[:tag]
            },
            config: build_config,
            skip_resolv_updates: true,
            skip_etc_hosts_fix: true,
            paranoid: false,
            hosts: {
                apt_cache: false,
                npm_cache: false
            },
            cache_options: {
                type: 's3',
                fetch_timeout: 600,
                push_timeout: 4800,
                s3: {
                    bucket: 's3_bucket',
                    secret_access_key: 's3_secret_access_key',
                    access_key_id: 's3_access_key_id'
                }
            }
        }
      end

      def matrix_build_config(matrix_entry)
        matrix_build_config = {}
        matrix_entry.mapping.each_key do |key|
          # call method to get matrix entry specialization for each mapped key
          # because Matrix::Entry redefines method for modified keys
          matrix_build_config[key] = matrix_entry.method(key).call()
        end

        if matrix_entry.respond_to? :matrix_attributes
          matrix_env = matrix_entry.matrix_attributes[:env]
        else
          matrix_env = parameters.env.matrix if parameters.env
        end

        # workaround for broken matrix_entry.global
        inherited_env = parameters.env.global if parameters.env
        matrix_build_config['env'] = [*matrix_env, *inherited_env].compact

        # use eval to convert back to simple represtentation
        eval(matrix_build_config.to_s)
      end

      def matrix_attributes(matrix_entry)
        if matrix_entry.respond_to? :matrix_attributes
          eval(matrix_entry.matrix_attributes.to_s)
        else
          nil
        end
      end

      def matrix_key(matrix_entry)
        attributes = matrix_attributes(matrix_entry)
        return 'default' unless attributes
        Digest::SHA1.hexdigest(attributes.to_s).to_s
      end

      def check_branch_constraint
        if current_branch == 'gh-pages'
          false
        elsif not parameters.branches
          true
        elsif parameters.branches.only
          false unless parameters.branches.only.include? current_branch
        elsif parameters.branches.except
          false if parameters.branches.except.include? current_branch
        end
      end

      def current_build_number
        @current_build_number ||= options[:build_number]
        @current_build_number ||= 1
      end

      def current_branch
        @current_branch ||= options[:current_branch] if options[:current_branch]
        @current_branch ||= `git symbolic-ref --short HEAD`.strip
      end

      def current_commit
        @current_commit ||= `git rev-parse --short HEAD`.strip
      end

      def remote_origin
        @remote_origin ||= `git config remote.origin.url`.strip
      end

      def remote_slug
        @remote_slug ||= remote_origin.split(':').last.split('/')[-2..-1].join('/').sub('.git', '').strip
      end

      def ssh_key
        @ssh_key ||= `cat ~/.ssh/id_rsa`.strip
      end

      def before_commit
        '0000000'
      end

      def parameters
        @parameters ||= Travis::Yaml.parse!(travis_yaml)
      end

      def matrix_entries
        @matrix_entries ||= Travis::Yaml.matrix(travis_yaml)
      end

      def travis_yaml
        @yaml ||= File.read('.travis.yml')
      end

      def ci_config
        @config ||= YAML.load('~/.polidea-ci.yml') if File.exist?('~/.polidea-ci.yml')
        @config ||= {}
      end

      def runner_script
        File.join(path_to_resources, 'run_script')
      end

      def path_to_resources
        File.join(File.dirname(File.expand_path(__FILE__)), '../../res')
      end
    end
  end
end
