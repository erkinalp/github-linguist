require 'linguist/configuration'

module Linguist
  class Context
    attr_reader :strategies, :language_registry, :configuration, :strategy_registry
    
    def initialize(strategies: nil, language_registry: nil, configuration: nil, 
                   enable_strategy_caching: false, enable_confidence_scoring: false)
      @strategies = strategies || DEFAULT_STRATEGIES
      @language_registry = language_registry || Language
      @configuration = configuration || Configuration.default
      
      # Create strategy registry if caching or confidence scoring is enabled
      if enable_strategy_caching || enable_confidence_scoring
        require 'linguist/strategy_registry'
        @strategy_registry = StrategyRegistry.new(
          @strategies,
          enable_caching: enable_strategy_caching,
          enable_confidence_scoring: enable_confidence_scoring
        )
      else
        @strategy_registry = nil
      end
    end
    
    DEFAULT_STRATEGIES = [
      Linguist::Strategy::Modeline,
      Linguist::Strategy::Filename,
      Linguist::Shebang,
      Linguist::Strategy::Extension,
      Linguist::Strategy::XML,
      Linguist::Strategy::Manpage,
      Linguist::Heuristics,
      Linguist::Classifier
    ].freeze
  end
  
  DEFAULT_CONTEXT = Context.new.freeze
end
