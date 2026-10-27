module OmniAgent
  class IngestJob < ActiveJob::Base
    # The record was deleted before or while the job ran; there's nothing to ingest.
    discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound
    # No loader can read the file, so retrying won't help.
    discard_on OmniAgent::UnsupportedDocumentError

    def perform(record)
      record.ingest!
    end
  end
end
