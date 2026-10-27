module OmniAgent
  class EmbedJob < ActiveJob::Base
    # The record was deleted before the job ran; there's nothing to embed.
    discard_on ActiveJob::DeserializationError

    def perform(record)
      record.embed!
    end
  end
end
