module Linguist
  class Configuration
    attr_reader :max_blob_size, :heuristics_consider_bytes, :classifier_consider_bytes
    
    def initialize(
      max_blob_size: 128 * 1024,
      heuristics_consider_bytes: 50 * 1024,
      classifier_consider_bytes: 50 * 1024
    )
      @max_blob_size = max_blob_size
      @heuristics_consider_bytes = heuristics_consider_bytes
      @classifier_consider_bytes = classifier_consider_bytes
    end
    
    def self.default
      @default ||= new
    end
  end
end
