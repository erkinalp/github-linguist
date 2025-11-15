require_relative "./helper"
require 'linguist/strategy_registry'

class TestStrategyRegistry < Minitest::Test
  include Linguist

  def setup
    @strategies = [
      Linguist::Strategy::Modeline,
      Linguist::Strategy::Filename,
      Linguist::Shebang,
      Linguist::Strategy::Extension
    ]
  end

  def test_strategy_registry_initialization
    registry = StrategyRegistry.new(@strategies)
    assert_equal @strategies, registry.strategies
    refute registry.enable_caching
    refute registry.enable_confidence_scoring
  end

  def test_strategy_registry_with_caching_enabled
    registry = StrategyRegistry.new(@strategies, enable_caching: true)
    assert registry.enable_caching
  end

  def test_strategy_registry_with_confidence_scoring_enabled
    registry = StrategyRegistry.new(@strategies, enable_confidence_scoring: true)
    assert registry.enable_confidence_scoring
  end

  def test_strategy_registry_run_without_caching
    registry = StrategyRegistry.new(@strategies)
    blob = sample_blob("Ruby/foo.rb")
    candidates = [Language["Ruby"], Language["Python"]]
    
    result = registry.run(blob, candidates)
    assert_equal Language["Ruby"], result
  end

  def test_strategy_registry_run_with_caching
    registry = StrategyRegistry.new(@strategies, enable_caching: true)
    blob = sample_blob("Ruby/foo.rb")
    candidates = [Language["Ruby"], Language["Python"]]
    
    # First call should compute and cache
    result1 = registry.run(blob, candidates)
    assert_equal Language["Ruby"], result1
    
    # Second call should use cache
    result2 = registry.run(blob, candidates)
    assert_equal Language["Ruby"], result2
    assert_equal result1.object_id, result2.object_id
  end

  def test_strategy_registry_cache_stats
    registry = StrategyRegistry.new(@strategies, enable_caching: true)
    
    stats = registry.cache_stats
    assert stats[:enabled]
    assert_equal 0, stats[:size]
    
    blob = sample_blob("Ruby/foo.rb")
    candidates = [Language["Ruby"], Language["Python"]]
    registry.run(blob, candidates)
    
    stats = registry.cache_stats
    assert_equal 1, stats[:size]
  end

  def test_strategy_registry_cache_stats_disabled
    registry = StrategyRegistry.new(@strategies)
    
    stats = registry.cache_stats
    refute stats[:enabled]
  end

  def test_strategy_registry_clear_cache
    registry = StrategyRegistry.new(@strategies, enable_caching: true)
    blob = sample_blob("Ruby/foo.rb")
    candidates = [Language["Ruby"], Language["Python"]]
    
    registry.run(blob, candidates)
    assert_equal 1, registry.cache_stats[:size]
    
    registry.clear_cache
    assert_equal 0, registry.cache_stats[:size]
  end

  def test_context_with_strategy_caching
    context = Context.new(enable_strategy_caching: true)
    assert context.strategy_registry
    assert context.strategy_registry.enable_caching
  end

  def test_context_with_confidence_scoring
    context = Context.new(enable_confidence_scoring: true)
    assert context.strategy_registry
    assert context.strategy_registry.enable_confidence_scoring
  end

  def test_context_with_both_features
    context = Context.new(
      enable_strategy_caching: true,
      enable_confidence_scoring: true
    )
    assert context.strategy_registry
    assert context.strategy_registry.enable_caching
    assert context.strategy_registry.enable_confidence_scoring
  end

  def test_context_without_features
    context = Context.new
    assert_nil context.strategy_registry
  end

  def test_default_context_unchanged
    # DEFAULT_CONTEXT should not have strategy registry
    assert_nil Linguist::DEFAULT_CONTEXT.strategy_registry
  end

  def test_high_confidence_strategies
    high_confidence = StrategyRegistry::HIGH_CONFIDENCE_STRATEGIES
    assert high_confidence.include?('Linguist::Strategy::Modeline')
    assert high_confidence.include?('Linguist::Strategy::Filename')
    assert high_confidence.include?('Linguist::Shebang')
  end

  def test_backward_compatibility_context_initialization
    # Old-style initialization should still work
    context = Context.new(
      strategies: @strategies,
      language_registry: Language,
      configuration: Configuration.default
    )
    
    assert_equal @strategies, context.strategies
    assert_equal Language, context.language_registry
    assert_equal Configuration.default, context.configuration
    assert_nil context.strategy_registry
  end
end
