module OmniAgent
  class EmbedJob < ApplicationJob
    def perform(record)
      record.embed!
    end
  end
end
