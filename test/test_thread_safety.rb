require_relative "./helper"
require 'linguist/cache_facade'

class TestThreadSafety < Minitest::Test
  include Linguist

  def test_cache_facade_fetch
    cache = CacheFacade.new
    result = cache.fetch(:test) { "test_value" }
    assert_equal "test_value", result
    assert_equal "test_value", cache.get(:test)
  end

  def test_cache_facade_fetch_only_computes_once
    cache = CacheFacade.new
    call_count = 0
    
    3.times do
      cache.fetch(:test) { call_count += 1; "value" }
    end
    
    assert_equal 1, call_count
  end

  def test_cache_facade_set_and_get
    cache = CacheFacade.new
    cache.set(:key, "value")
    assert_equal "value", cache.get(:key)
  end

  def test_cache_facade_clear
    cache = CacheFacade.new
    cache.set(:key, "value")
    cache.clear
    assert_nil cache.get(:key)
  end

  def test_cache_facade_key?
    cache = CacheFacade.new
    refute cache.key?(:test)
    cache.set(:test, "value")
    assert cache.key?(:test)
  end

  def test_cache_facade_thread_safety
    cache = CacheFacade.new
    threads = []
    results = []
    
    10.times do |i|
      threads << Thread.new do
        result = cache.fetch(:counter) { 0 }
        results << result
      end
    end
    
    threads.each(&:join)
    
    # All threads should get the same value (0)
    assert_equal [0] * 10, results
  end

  def test_samples_cache_threadsafe
    cache_facade = CacheFacade.new
    samples = Samples.cache_threadsafe(cache_facade)
    
    assert samples.is_a?(Hash)
    assert samples.key?('centroids')
    
    # Verify it's cached
    assert cache_facade.key?(:samples)
  end

  def test_samples_cache_threadsafe_without_facade
    samples = Samples.cache_threadsafe
    
    assert samples.is_a?(Hash)
    assert samples.key?('centroids')
  end

  def test_samples_cache_threadsafe_multi_threaded
    cache_facade = CacheFacade.new
    threads = []
    results = []
    
    5.times do
      threads << Thread.new do
        results << Samples.cache_threadsafe(cache_facade)
      end
    end
    
    threads.each(&:join)
    
    # All threads should get the same samples object
    first_result = results.first
    results.each do |result|
      assert_equal first_result.object_id, result.object_id
    end
  end

  def test_heuristics_load_threadsafe
    cache_facade = CacheFacade.new
    Heuristics.load_threadsafe(cache_facade)
    
    # Verify heuristics are loaded
    assert Heuristics.all.any?
    
    # Verify it's cached
    assert cache_facade.key?(:heuristics)
  end

  def test_heuristics_load_threadsafe_without_facade
    Heuristics.load_threadsafe
    
    # Verify heuristics are loaded
    assert Heuristics.all.any?
  end

  def test_heuristics_load_threadsafe_multi_threaded
    cache_facade = CacheFacade.new
    threads = []
    
    10.times do
      threads << Thread.new do
        Heuristics.load_threadsafe(cache_facade)
      end
    end
    
    threads.each(&:join)
    
    # Verify heuristics are loaded correctly
    assert Heuristics.all.any?
  end

  def test_backward_compatibility_samples_cache
    # Old method should still work
    samples = Samples.cache
    assert samples.is_a?(Hash)
    assert samples.key?('centroids')
  end

  def test_backward_compatibility_heuristics_load
    # Old method should still work
    Heuristics.load
    assert Heuristics.all.any?
  end
end
