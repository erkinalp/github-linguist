require_relative "./helper"

class TestContext < Minitest::Test
  include Linguist

  def test_configuration_default
    config = Linguist::Configuration.default
    assert_equal 128 * 1024, config.max_blob_size
    assert_equal 50 * 1024, config.heuristics_consider_bytes
    assert_equal 50 * 1024, config.classifier_consider_bytes
  end

  def test_configuration_custom
    config = Linguist::Configuration.new(
      max_blob_size: 256 * 1024,
      heuristics_consider_bytes: 100 * 1024,
      classifier_consider_bytes: 100 * 1024
    )
    assert_equal 256 * 1024, config.max_blob_size
    assert_equal 100 * 1024, config.heuristics_consider_bytes
    assert_equal 100 * 1024, config.classifier_consider_bytes
  end

  def test_context_default_strategies
    context = Linguist::Context.new
    assert_equal 8, context.strategies.length
    assert_equal Linguist::Strategy::Modeline, context.strategies[0]
    assert_equal Linguist::Strategy::Filename, context.strategies[1]
    assert_equal Linguist::Shebang, context.strategies[2]
    assert_equal Linguist::Strategy::Extension, context.strategies[3]
    assert_equal Linguist::Strategy::XML, context.strategies[4]
    assert_equal Linguist::Strategy::Manpage, context.strategies[5]
    assert_equal Linguist::Heuristics, context.strategies[6]
    assert_equal Linguist::Classifier, context.strategies[7]
  end

  def test_context_custom_strategies
    custom_strategies = [
      Linguist::Strategy::Extension,
      Linguist::Classifier
    ]
    context = Linguist::Context.new(strategies: custom_strategies)
    assert_equal 2, context.strategies.length
    assert_equal Linguist::Strategy::Extension, context.strategies[0]
    assert_equal Linguist::Classifier, context.strategies[1]
  end

  def test_context_default_language_registry
    context = Linguist::Context.new
    assert_equal Linguist::Language, context.language_registry
  end

  def test_context_default_configuration
    context = Linguist::Context.new
    assert_equal Linguist::Configuration.default, context.configuration
  end

  def test_default_context_constant
    assert_instance_of Linguist::Context, Linguist::DEFAULT_CONTEXT
    assert Linguist::DEFAULT_CONTEXT.frozen?
  end

  def test_default_context_preserves_existing_behavior
    blob = sample_blob_memory("Ruby/foo.rb")
    
    # Old API still works (without context parameter)
    lang1 = Linguist.detect(blob)
    
    # New API with default context produces same result
    lang2 = Linguist.detect(blob, context: Linguist::DEFAULT_CONTEXT)
    
    assert_equal lang1, lang2
    assert_equal Linguist::Language["Ruby"], lang1
  end

  def test_custom_context_allows_strategy_customization
    # Custom strategy order (only Extension and Classifier)
    custom_strategies = [
      Linguist::Strategy::Extension,
      Linguist::Classifier
    ]
    context = Linguist::Context.new(strategies: custom_strategies)
    
    blob = sample_blob_memory("Ruby/foo.rb")
    lang = Linguist.detect(blob, context: context)
    
    # Should still detect Ruby correctly
    assert_equal Linguist::Language["Ruby"], lang
  end

  def test_detect_with_default_context_matches_original_behavior
    # Test multiple file types to ensure backward compatibility
    test_cases = [
      ["Ruby/foo.rb", "Ruby"],
      ["JavaScript/dude.js", "JavaScript"],
      ["Python/django-models-base.py", "Python"],
      ["C/array.c", "C"]
    ]
    
    test_cases.each do |path, expected_language|
      blob = sample_blob_memory(path)
      
      # Without context parameter
      lang1 = Linguist.detect(blob)
      
      # With explicit default context
      lang2 = Linguist.detect(blob, context: Linguist::DEFAULT_CONTEXT)
      
      assert_equal lang1, lang2, "Results differ for #{path}"
      assert_equal Linguist::Language[expected_language], lang1, "Wrong language for #{path}"
    end
  end

  def test_context_strategies_frozen
    assert Linguist::Context::DEFAULT_STRATEGIES.frozen?
  end

  def test_detect_respects_context_strategies
    # Create a context with only Extension strategy
    context = Linguist::Context.new(
      strategies: [Linguist::Strategy::Extension]
    )
    
    # This should work because .rb extension is recognized
    blob = sample_blob_memory("Ruby/foo.rb")
    lang = Linguist.detect(blob, context: context)
    assert_equal Linguist::Language["Ruby"], lang
  end

  def test_detect_with_empty_strategies_returns_nil
    # Create a context with no strategies
    context = Linguist::Context.new(strategies: [])
    
    blob = sample_blob_memory("Ruby/foo.rb")
    lang = Linguist.detect(blob, context: context)
    
    # Should return nil because no strategies to detect language
    assert_nil lang
  end

  def test_context_immutability
    # DEFAULT_CONTEXT should be frozen
    assert Linguist::DEFAULT_CONTEXT.frozen?
    
    # Attempting to modify should raise an error
    assert_raises(FrozenError) do
      Linguist::DEFAULT_CONTEXT.instance_variable_set(:@strategies, [])
    end
  end
end
