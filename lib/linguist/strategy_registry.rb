require 'digest/sha2'

module Linguist
  # Strategy registry with result caching and confidence scoring
  #
  # This class provides a flexible strategy pipeline with optional features:
  # - Result caching for repeated detections
  # - Confidence-based early exit
  # - Strategy execution tracking
  #
  # Example:
  #   registry = StrategyRegistry.new(strategies, enable_caching: true)
  #   result = registry.run(blob, candidates)
  class StrategyRegistry
    attr_reader :strategies, :enable_caching, :enable_confidence_scoring
    
    # High-confidence strategies that can trigger early exit
    HIGH_CONFIDENCE_STRATEGIES = [
      'Linguist::Strategy::Modeline',
      'Linguist::Strategy::Filename',
      'Linguist::Shebang'
    ].freeze
    
    def initialize(strategies, enable_caching: false, enable_confidence_scoring: false)
      @strategies = strategies
      @enable_caching = enable_caching
      @enable_confidence_scoring = enable_confidence_scoring
      @cache = {} if @enable_caching
    end
    
    # Public: Run strategies on a blob to detect language
    #
    # blob       - An object that quacks like a blob
    # candidates - Array of Language objects
    #
    # Returns a Language object or nil
    def run(blob, candidates)
      # Check cache if enabled
      if @enable_caching
        cache_key = cache_key_for(blob, candidates)
        return @cache[cache_key] if @cache.key?(cache_key)
      end
      
      result = nil
      @strategies.each do |strategy|
        language = strategy.call(blob, candidates)
        
        if language
          # Handle both single language and array of languages
          result = language.is_a?(Array) ? language.first : language
          
          # Early exit for high-confidence strategies if enabled
          if @enable_confidence_scoring && high_confidence_strategy?(strategy)
            break
          end
        end
      end
      
      # Cache result if enabled
      if @enable_caching
        @cache[cache_key] = result
      end
      
      result
    end
    
    # Public: Clear the cache
    #
    # Returns nothing
    def clear_cache
      @cache.clear if @enable_caching
      nil
    end
    
    # Public: Get cache statistics
    #
    # Returns a Hash with cache stats
    def cache_stats
      return { enabled: false } unless @enable_caching
      
      {
        enabled: true,
        size: @cache.size,
        keys: @cache.keys.size
      }
    end
    
    private
    
    # Internal: Generate cache key for a blob and candidates
    #
    # blob       - An object that quacks like a blob
    # candidates - Array of Language objects
    #
    # Returns a String cache key
    def cache_key_for(blob, candidates)
      # Use blob name and candidate names to generate cache key
      candidate_names = candidates.map(&:name).sort.join(',')
      "#{blob.name}:#{candidate_names}"
    end
    
    # Internal: Check if a strategy is high-confidence
    #
    # strategy - A strategy object
    #
    # Returns true if high-confidence, false otherwise
    def high_confidence_strategy?(strategy)
      strategy_name = strategy.class.name
      HIGH_CONFIDENCE_STRATEGIES.include?(strategy_name)
    end
  end
end
