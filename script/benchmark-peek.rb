#!/usr/bin/env ruby

require 'bundler/setup'
require 'linguist'
require 'benchmark'

# Benchmark script to measure I/O reduction from peek() method

class MockBlob
  attr_reader :name, :data, :bytes_loaded
  
  def initialize(name, data)
    @name = name
    @data = data
    @bytes_loaded = 0
  end
  
  def peek(n)
    @bytes_loaded = [n, @data.bytesize].min
    @data[0...n]
  end
  
  def symlink?
    false
  end
  
  def respond_to?(method)
    [:name, :data, :peek, :symlink?].include?(method) || super
  end
end

class MockBlobWithoutPeek
  attr_reader :name, :data, :bytes_loaded
  
  def initialize(name, data)
    @name = name
    @data = data
    @bytes_loaded = @data.bytesize
  end
  
  def symlink?
    false
  end
  
  def respond_to?(method)
    [:name, :data, :symlink?].include?(method) || super
  end
end

# Generate test data
def generate_test_data(size)
  # Generate realistic code-like data
  lines = []
  keywords = ['def', 'class', 'if', 'else', 'for', 'while', 'return', 'import', 'function']
  
  while lines.join("\n").bytesize < size
    line = "#{keywords.sample} test_#{rand(1000)} { /* code */ }"
    lines << line
  end
  
  lines.join("\n")[0...size]
end

puts "Benchmark: LazyBlob#peek I/O Reduction"
puts "=" * 60
puts

# Test with different file sizes
file_sizes = [
  [10 * 1024, "10 KB"],
  [50 * 1024, "50 KB"],
  [100 * 1024, "100 KB"],
  [128 * 1024, "128 KB (MAX_SIZE)"]
]

file_sizes.each do |size, label|
  puts "File size: #{label}"
  data = generate_test_data(size)
  
  # Test with peek
  blob_with_peek = MockBlob.new("test.rb", data)
  Linguist::Heuristics.call(blob_with_peek, [])
  bytes_with_peek = blob_with_peek.bytes_loaded
  
  # Test without peek
  blob_without_peek = MockBlobWithoutPeek.new("test.rb", data)
  Linguist::Heuristics.call(blob_without_peek, [])
  bytes_without_peek = blob_without_peek.bytes_loaded
  
  reduction = ((bytes_without_peek - bytes_with_peek).to_f / bytes_without_peek * 100).round(1)
  
  puts "  Without peek: #{bytes_without_peek} bytes loaded"
  puts "  With peek:    #{bytes_with_peek} bytes loaded"
  puts "  Reduction:    #{reduction}%"
  puts
end

puts "=" * 60
puts "Summary:"
puts "- Heuristics uses peek(#{Linguist::Heuristics::HEURISTICS_CONSIDER_BYTES}) = #{Linguist::Heuristics::HEURISTICS_CONSIDER_BYTES / 1024} KB"
puts "- Classifier uses peek(#{Linguist::Classifier::CLASSIFIER_CONSIDER_BYTES}) = #{Linguist::Classifier::CLASSIFIER_CONSIDER_BYTES / 1024} KB"
puts "- MAX_SIZE = #{Linguist::LazyBlob::MAX_SIZE / 1024} KB"
puts
puts "Expected I/O reduction: ~60% for files >= 128 KB"
puts "  (loading 50 KB instead of 128 KB)"
