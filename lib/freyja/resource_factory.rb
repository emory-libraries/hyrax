# frozen_string_literal: true

module Freyja
  # Provides access to generic methods for converting to/from
  # {Valkyrie::Resource} and {Valkyrie::Persistence::Postgres::ORM::Resource}.
  class ResourceFactory < Valkyrie::Persistence::Postgres::ResourceFactory
    # @param object [Valkyrie::Persistence::Postgres::ORM::Resource] AR
    #   record to be converted.
    # @return [Valkyrie::Resource] Model representation of the AR record.
    def to_resource(object:)
      MigrateFilesFromFedoraJob.conditionally_perform_later(object:, resource_factory: self)
      super
    end

    ##
    # Responsible for conditionally enqueuing the file and thumbnail migration
    # logic of an ActiveFedora object.
    class MigrateFilesFromFedoraJob < Hyrax::ApplicationJob
      def self.already_migrated?(resource:)
        # NOTE: Because we're writing this code in a Freyja adapter, we're
        # assuming that we're using a Goddess strategy for lazy migration.
        query_service_for_migrating_to = Hyrax.query_service.services.first

        # TODO: Consider writing a custom query as this is slow compared to a
        # simple `SELECT COUNT(id) WHERE ids IN (?)'
        query_service_for_migrating_to.find_many_by_ids(ids: resource.file_ids).any?
      end
      ##
      # Check the conditions of the given object to see if it should be
      # enqueued.  Given how frequently the logic could fire, we don't want to
      # enqueue a load of jobs that all bail immediately.
      #
      # @param object [Valkyrie::Persistence::Postgres::ORM::Resource] AR
      #        record to be converted.
      def self.conditionally_perform_later(object:, resource_factory:)
        # TODO How might we consider handling a failed convert?  I believe we
        # should raise a loud exception as this is almost certainly a
        # configuration error.

        # Prevent infinite looping when converting a FileSet
        return :in_progress if Thread.current[:hyrax_migration_fileset_id] == object.id.to_s

        resource = ::Valkyrie::Persistence::Postgres::ORMConverter.new(object, resource_factory:).convert!

        # Only migrate files for file sets objects
        return :not_a_fileset unless resource.is_a?(Hyrax::FileSet) && resource.respond_to?(:file_ids)

        # Looking for low hanging fruit (e.g. not overly costly to perform) to
        # avoid flooding the job queue.
        #
        # TODO: Is there a better logic for this?  Maybe check if one or more of
        # the file_ids is in the storage adapter?
        return :already_migrated if already_migrated?(resource:)

        # NOTE: Should we pass the object and re-convert it?  We'll see how this all
        # works.
        perform_later(object)
      end

      ##
      # Favor {.conditionally_perform_later} as it performs guards on the
      # resource submission.
      #
      # @param resource [Object]
      def perform(object)
        Thread.current[:hyrax_migration_fileset_id] = object.id.to_s
        resource_factory = Hyrax.metadata_adapter.resource_factory

        resource = ::Valkyrie::Persistence::Postgres::ORMConverter.new(object, resource_factory:).convert!
        migrate_derivatives!(resource:)
        # need to reload file_set to get the derivative ids
        resource = Hyrax.query_service.find_by(id: resource.id)
        migrate_files!(resource: resource)
      ensure
        Thread.current[:hyrax_migration_fileset_id] = nil
      end

      private

      def migrate_derivatives!(resource:)
        # @todo should we trigger a job if the member is a child work?
        paths = Hyrax::DerivativePath.derivatives_for_reference(resource)
        paths.each do |path|
          container = container_for(path)
          mime_type = Marcel::MimeType.for(extension: File.extname(path))
          directives = { url: path, container: container, mime_type: mime_type }
          File.open(path, 'rb') do |content|
            Hyrax::ValkyriePersistDerivatives.call(content, directives)
          end
        end
      end

      ##
      # Move the ActiveFedora files out of ActiveFedora's domain and into the
      # configured {Hyrax.storage_adapter}'s domain.
      def migrate_files!(resource:)
        return unless resource.respond_to?(:file_ids)

        files = Hyrax.custom_queries.find_many_file_metadata_by_ids(ids: resource.file_ids)
        files.each do |file|
          # If it doesn't start with fedora, we've likely already migrated it.
          next unless /^fedora:/.match?(file.file_identifier.to_s)
          resource.file_ids.delete(file.id)

          Tempfile.create do |tempfile|
            tempfile.binmode
            tempfile.write(URI.open(file.file_identifier.to_s.gsub("fedora:", "http:")).read)
            tempfile.rewind

            # valkyrie_file = Hyrax.storage_adapter.upload(resource: resource, file: tempfile, original_filename: file.original_filename)
            valkyrie_file = Hyrax::ValkyrieUpload.file(
              filename: resource.label,
              file_set: resource,
              io: tempfile,
              use: file.pcdm_use.select {|use| Hyrax::FileMetadata::Use.use_list.include?(use)},
              user: User.find_or_initialize_by(User.user_key_field => resource.depositor),
              mime_type: file.mime_type,
              skip_derivatives: true
            )
          end
        end
      end

      ##
      # Map from the file name used for the derivative to a valid option for
      # container that ValkyriePersistDerivatives can convert into a
      # Hyrax::Metadata::Use
      #
      # @param filename [String] the name of the derivative file: i.e. 'x-thumbnail.jpg'
      # @return [String]
      def container_for(filename)
        # we want the portion between the '-' and the '.'
        file_blob = File.basename(filename, '.*').split('-').last

        case file_blob
        when 'thumbnail'
          'thumbnail_image'
        when 'txt', 'json', 'xml'
          'extracted_text'
        else
          'service_file'
        end
      end
    end
  end
end
