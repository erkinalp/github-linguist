require 'linguist/configuration'

module Linguist
  class Context
    attr_reader :strategies, :language_registry, :configuration
    
    def initialize(strategies: nil, language_registry: nil, configuration: nil)
      @strategies = strategies || DEFAULT_STRATEGIES
      @language_registry = language_registry || Language
      @configuration = configuration || Configuration.default
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
