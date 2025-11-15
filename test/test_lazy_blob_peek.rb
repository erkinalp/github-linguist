require_relative "./helper"

class PeekTrackingBlob
  attr_reader :name, :peek_called
  
  def initialize(name, data)
    @name = name
    @data = data
    @peek_called = false
  end
  
  def peek(n)
    @peek_called = true
    @data[0...n]
  end
  
  def data
    @data
  end
  
  def symlink?
    false
  end
end

class NoPeekBlob
  attr_reader :name
  
  def initialize(name, data)
    @name = name
    @data = data
  end
  
  def data
    @data
  end
  
  def symlink?
    false
  end
end

class TestLazyBlobPeek < Minitest::Test
  include Linguist

  def test_peek_method_exists_on_blob
    blob = sample_blob_memory("Ruby/foo.rb")
    assert blob.respond_to?(:peek)
  end

  def test_heuristics_backward_compatible
    blob = sample_blob_memory("Ruby/foo.rb")
    lang = Linguist.detect(blob)
    assert_equal Linguist::Language["Ruby"], lang
  end

  def test_classifier_backward_compatible
    blob = sample_blob_memory("JavaScript/dude.js")
    lang = Linguist.detect(blob)
    assert_equal Linguist::Language["JavaScript"], lang
  end

  def test_detection_results_unchanged
    test_cases = [
      ["Ruby/foo.rb", "Ruby"],
      ["JavaScript/dude.js", "JavaScript"],
      ["Python/django-models-base.py", "Python"],
      ["C/array.c", "C"]
    ]
    
    test_cases.each do |path, expected_language|
      blob = sample_blob_memory(path)
      lang = Linguist.detect(blob)
      assert_equal Linguist::Language[expected_language], lang, "Detection failed for #{path}"
    end
  end

  def test_heuristics_uses_peek_when_available
    data = "// Objective-C code\n#import <Foundation/Foundation.h>\n"
    blob = PeekTrackingBlob.new("test.m", data)
    
    Linguist::Heuristics.call(blob, [Linguist::Language["Objective-C"], Linguist::Language["Matlab"]])
    
    assert blob.peek_called, "Heuristics should use peek when available"
  end

  def test_classifier_uses_peek_when_available
    data = "def hello\n  puts 'world'\nend\n"
    blob = PeekTrackingBlob.new("test.rb", data)
    
    Linguist::Classifier.call(blob, [Linguist::Language["Ruby"], Linguist::Language["Python"]])
    
    assert blob.peek_called, "Classifier should use peek when available"
  end

  def test_heuristics_fallback_without_peek
    data = "// Objective-C code\n#import <Foundation/Foundation.h>\n"
    blob = NoPeekBlob.new("test.m", data)
    
    result = Linguist::Heuristics.call(blob, [Linguist::Language["Objective-C"], Linguist::Language["Matlab"]])
    
    assert result.is_a?(Array)
  end

  def test_classifier_fallback_without_peek
    data = "def hello\n  puts 'world'\nend\n"
    blob = NoPeekBlob.new("test.rb", data)
    
    result = Linguist::Classifier.call(blob, [Linguist::Language["Ruby"], Linguist::Language["Python"]])
    
    assert result.is_a?(Array)
  end
end
