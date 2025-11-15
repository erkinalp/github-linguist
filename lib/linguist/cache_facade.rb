require 'thread'

module Linguist
  # Thread-safe cache facade for global state management
  #
  # This class provides a thread-safe wrapper around cached data using Mutex.
  # It's designed to enable multi-threaded usage of Linguist without race conditions.
  #
  # Example:
  #   cache = CacheFacade.new
  #   cache.fetch(:samples) { Samples.load_samples }
  #   cache.get(:samples) # => cached samples data
  class CacheFacade
    def initialize
      @cache = {}
      @mutex = Mutex.new
    end

    # Public: Fetch a value from the cache, computing it if necessary
    #
    # key   - Symbol key to fetch
    # block - Block to compute value if not cached
    #
    # Returns the cached or computed value
    def fetch(key, &block)
      @mutex.synchronize do
        @cache[key] ||= block.call
      end
    end

    # Public: Get a value from the cache
    #
    # key - Symbol key to fetch
    #
    # Returns the cached value or nil
    def get(key)
      @mutex.synchronize do
        @cache[key]
      end
    end

    # Public: Set a value in the cache
    #
    # key   - Symbol key to set
    # value - Value to cache
    #
    # Returns the value
    def set(key, value)
      @mutex.synchronize do
        @cache[key] = value
      end
    end

    # Public: Clear the cache
    #
    # Returns nothing
    def clear
      @mutex.synchronize do
        @cache.clear
      end
      nil
    end

    # Public: Check if a key exists in the cache
    #
    # key - Symbol key to check
    #
    # Returns true if key exists, false otherwise
    def key?(key)
      @mutex.synchronize do
        @cache.key?(key)
      end
    end
  end
end
