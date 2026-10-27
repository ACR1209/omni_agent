module OmniAgent
  class EmbedJob < ApplicationJob
    # The record was deleted before the job ran; there's nothing to embed.
    discard_on ActiveJob::DeserializationError

    def perform(record)
      record.embed!
    end
  end
end
