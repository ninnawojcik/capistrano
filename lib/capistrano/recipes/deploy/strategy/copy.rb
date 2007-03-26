require 'capistrano/recipes/deploy/strategy/base'
require 'fileutils'

module Capistrano
  module Deploy
    module Strategy

      # This class implements the strategy for deployments which work
      # by preparing the source code locally, compressing it, copying the
      # file to each target host, and uncompressing it to the deployment
      # directory.
      #
      # By default, the SCM checkout command is used to obtain the local copy
      # of the source code. If you would rather use the export operation,
      # you can set the :copy_strategy variable to :export.
      #
      # This deployment strategy supports a special variable,
      # :copy_compression, which must be one of :gzip, :bz2, or
      # :zip, and which specifies how the source should be compressed for
      # transmission to each host.
      class Copy < Base
        # Obtains a copy of the source code locally (via the #command method),
        # compresses it to a single file, copies that file to all target
        # servers, and uncompresses it on each of them into the deployment
        # directory.
        def deploy!
          logger.debug "getting (via #{copy_strategy}) revision #{revision} to #{destination}"
          system(command)
          File.open(File.join(destination, "REVISION"), "w") { |f| f.puts(revision) }

          logger.trace "compressing #{destination} to #{filename}"
          system(compress(destination, filename))

          put File.read(filename), remote_filename
          run "cd #{configuration[:releases_path]} && #{decompress(remote_filename)} && rm #{remote_filename}"
        ensure
          FileUtils.rm filename rescue nil
          FileUtils.rm_rf destination rescue nil
        end

        private

          # Returns the basename of the release_path, which will be used to
          # name the local copy and archive file.
          def destination
            @destination ||= File.basename(configuration[:release_path])
          end

          # Returns the value of the :copy_strategy variable, defaulting to
          # :checkout if it has not been set.
          def copy_strategy
            @copy_strategy ||= configuration.fetch(:copy_strategy, :checkout)
          end

          # Should return the command(s) necessary to obtain the source code
          # locally.
          def command
            @command ||= case copy_strategy
            when :checkout
              source.checkout(revision, destination)
            when :export
              source.export(revision, destination)
            end
          end

          # Returns the name of the file that the source code will be
          # compressed to.
          def filename
            @filename ||= "#{destination}.#{compression_extension}"
          end

          # The location on the remote server where the file should be
          # temporarily stored.
          def remote_filename
            @remote_filename ||= "/tmp/#{filename}"
          end

          # The compression method to use, defaults to :gzip.
          def compression
            configuration[:copy_compression] || :gzip
          end

          # Returns the file extension used for the compression method in
          # question.
          def compression_extension
            case compression
            when :gzip, :gz   then "tar.gz"
            when :bzip2, :bz2 then "tar.bz2"
            when :zip         then "zip"
            else raise ArgumentError, "invalid compression type #{compression.inspect}"
            end
          end

          # Returns the command necessary to compress the given directory
          # into the given file.
          def compress(directory, file)
            case compression
            when :gzip, :gz   then "tar czf #{file} #{directory}"
            when :bzip2, :bz2 then "tar cjf #{file} #{directory}"
            when :zip         then "zip -qr #{file} #{directory}"
            end
          end

          # Returns the command necessary to decompress the given file,
          # relative to the current working directory. It must also
          # preserve the directory structure in the file.
          def decompress(file)
            case compression
            when :gzip, :gz   then "tar xzf #{file}"
            when :bzip2, :bz2 then "tar xjf #{file}"
            when :zip         then "unzip -q #{file}"
            end
          end
      end

    end
  end
end
