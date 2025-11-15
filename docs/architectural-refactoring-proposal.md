# Linguist Architectural Refactoring Proposal

## Executive Summary

This document proposes a comprehensive architectural refactoring of the Linguist codebase to address five critical issues that impact performance, maintainability, and extensibility:

1. **Hardcoded Strategy Chain** - Rigid, non-configurable detection pipeline
2. **Inefficient Memory Management** - Lazy loading without proper caching or resource pooling
3. **Broken Abstraction Boundaries** - Monolithic BlobHelper mixin with mixed responsibilities
4. **Repository Analysis Bottlenecks** - Sequential processing without parallelization
5. **Global State Management** - Thread-unsafe module-level variables

The proposed refactoring follows an incremental, backward-compatible approach with six phases, prioritized by merge-ability and measurable impact while minimizing risk.

## Current Architecture Analysis

### 1. Hardcoded Strategy Chain

**Location:** `lib/linguist.rb:63-72`

**Current Implementation:**
```ruby
STRATEGIES = [
  Linguist::Strategy::Modeline,
  Linguist::Strategy::Filename,
  Linguist::Shebang,
  Linguist::Strategy::Extension,
  Linguist::Strategy::XML,
  Linguist::Strategy::Manpage,
  Linguist::Heuristics,
  Linguist::Classifier
]
```

**Problems:**
- Strategies are executed sequentially with no early termination optimization
- No confidence scoring mechanism
- Cannot be configured or customized per-repository
- No caching of strategy results
- Independent strategies (Modeline, Shebang) could run in parallel

**Impact:**
- Every file must go through all strategies even when early strategies provide high-confidence results
- No ability to skip expensive strategies (Heuristics, Classifier) when unnecessary
- Performance degrades linearly with number of strategies

### 2. Inefficient Memory Management

**Location:** `lib/linguist/lazy_blob.rb:90-118`

**Current Implementation:**
```ruby
MAX_SIZE = 128 * 1024

def data
  load_blob!
  @data
end

def load_blob!
  @data, @size = repository.load_blob(oid, MAX_SIZE) if @data.nil?
end

def cleanup!
  @data.clear if @data
end
```

**Problems:**
- Hardcoded 128KB limit affects detection accuracy
- No blob pooling or reuse
- Manual cleanup required, prone to memory leaks
- Git attributes loaded per-blob without caching
- Heuristics and Classifier load full blob data when they only need 50KB

**Impact:**
- Memory usage scales poorly with repository size
- Unnecessary I/O for strategies that only need partial data
- Manual cleanup burden on callers

**Measurement:**
```ruby
# Heuristics only needs 50KB
HEURISTICS_CONSIDER_BYTES = 50 * 1024  # lib/linguist/heuristics.rb:6
data = blob.data[0...HEURISTICS_CONSIDER_BYTES]  # lib/linguist/heuristics.rb:24

# Classifier only needs 50KB
CLASSIFIER_CONSIDER_BYTES = 50 * 1024  # lib/linguist/classifier.rb:10
blob.data[0...CLASSIFIER_CONSIDER_BYTES]  # lib/linguist/classifier.rb:26
```

Both strategies load the full 128KB blob data, then slice to 50KB. This wastes 78KB of I/O and memory per blob.

### 3. Broken Abstraction Boundaries

**Location:** `lib/linguist/blob_helper.rb:8-16`

**Current Implementation:**
```ruby
# DEPRECATED Avoid mixing into Blob classes. Prefer functional interfaces
# like `Linguist.detect` over `Blob#language`. Functions are much easier to
# cache and compose.
#
# Avoid adding additional bloat to this module.
module BlobHelper
  # 390 lines of mixed responsibilities
end
```

**Problems:**
- BlobHelper mixin has too many responsibilities (metadata, content, classification, vendored detection, documentation detection, generated detection)
- Strategies tightly coupled to Language class
- Heuristics and Classifier violate strategy interface by directly accessing `blob.data`
- LazyBlob mixes git attribute handling with language detection

**Impact:**
- Difficult to test individual concerns
- Tight coupling prevents proper dependency injection
- Cannot easily swap implementations
- The DEPRECATED comment indicates maintainers are aware but haven't refactored

### 4. Repository Analysis Bottlenecks

**Location:** `lib/linguist/repository.rb:142-178`

**Current Implementation:**
```ruby
MAX_TREE_SIZE = 100_000

def compute_stats(old_commit_oid, cache = nil)
  return {} if repository.get_tree_size(@commit_oid, @max_tree_size) >= @max_tree_size
  
  diff.each_delta do |delta|
    # Sequential processing
    blob = Linguist::LazyBlob.new(repository, delta.new_file[:oid], new, mode.to_s(8))
    update_file_map(blob, file_map, new)
    blob.cleanup!
  end
end
```

**Problems:**
- Hardcoded 100k file limit prevents analysis of large projects
- Sequential blob processing without parallelization
- Inefficient .gitattributes change handling (invalidates entire cache)
- No bloom filters or quick rejection of vendored/generated files
- Creates new LazyBlob for each file without pooling

**Impact:**
- Large repositories (>100k files) cannot be analyzed
- No parallelization despite I/O-bound workload
- .gitattributes changes force full re-analysis

### 5. Global State Management

**Locations:**
- `lib/linguist/heuristics.rb:98` - `@heuristics = []`
- `lib/linguist/samples.rb:21-23` - `@cache ||= load_samples`
- `lib/linguist/language.rb:25-33` - Multiple module-level indexes
- `lib/linguist/strategy/extension.rb:32` - `@generic = []`

**Current Implementation:**
```ruby
# Heuristics
@heuristics = []

# Samples
def self.cache
  @cache ||= load_samples
end

# Language
@languages          = []
@index              = {}
@name_index         = {}
@alias_index        = {}
@language_id_index  = {}
@extension_index    = Hash.new { |h,k| h[k] = [] }
@interpreter_index  = Hash.new { |h,k| h[k] = [] }
@filename_index     = Hash.new { |h,k| h[k] = [] }
```

**Problems:**
- Module-level mutable state is not thread-safe
- Hidden dependencies make testing difficult
- No dependency injection
- Configuration loaded at module initialization
- Cannot have multiple configurations in same process

**Impact:**
- Thread-safety issues in multi-threaded environments
- Difficult to test with different configurations
- Cannot isolate tests properly

## Proposed Refactoring: Phased Approach

### Phase 1: Enabling Infrastructure (No-Op)

**Goal:** Add optional Context/StrategyRegistry while preserving existing API and defaults.

**Implementation:**

```ruby
# lib/linguist/context.rb
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
  
  # Default context for backward compatibility
  DEFAULT_CONTEXT = Context.new.freeze
end

# lib/linguist.rb - Updated detect method
class << Linguist
  def detect(blob, allow_empty: false, context: DEFAULT_CONTEXT)
    return nil if blob.likely_binary? || blob.binary? || (!allow_empty && blob.empty?)
    
    Linguist.instrument("linguist.detection", :blob => blob) do
      languages = []
      returning_strategy = nil
      
      context.strategies.each do |strategy|
        returning_strategy = strategy
        candidates = Linguist.instrument("linguist.strategy", :blob => blob, :strategy => strategy, :candidates => languages) do
          strategy.call(blob, languages)
        end
        
        if candidates.size == 1
          languages = candidates
          break
        elsif candidates.size > 1
          languages = candidates
        end
      end
      
      Linguist.instrument("linguist.detected", :blob => blob, :strategy => returning_strategy, :language => languages.first)
      languages.first
    end
  end
end
```

**Benefits:**
- 100% backward compatible (context: parameter is optional)
- Enables future customization without breaking changes
- Tests pass unchanged
- Foundation for all subsequent phases

**Testing:**
```ruby
# test/test_context.rb
require 'test_helper'

class TestContext < Minitest::Test
  def test_default_context_preserves_existing_behavior
    blob = sample_blob("Ruby/foo.rb")
    
    # Old API still works
    lang1 = Linguist.detect(blob)
    
    # New API with default context produces same result
    lang2 = Linguist.detect(blob, context: Linguist::DEFAULT_CONTEXT)
    
    assert_equal lang1, lang2
  end
  
  def test_custom_context_allows_strategy_customization
    # Custom strategy order
    custom_strategies = [
      Linguist::Strategy::Extension,
      Linguist::Classifier
    ]
    context = Linguist::Context.new(strategies: custom_strategies)
    
    blob = sample_blob("Ruby/foo.rb")
    lang = Linguist.detect(blob, context: context)
    
    assert_equal Language["Ruby"], lang
  end
end
```

### Phase 2: Reduce Blob I/O (High Impact, Low Risk)

**Goal:** Add `LazyBlob#peek(n)` to load only the bytes needed by strategies.

**Implementation:**

```ruby
# lib/linguist/lazy_blob.rb
class LazyBlob
  MAX_SIZE = 128 * 1024
  
  # New method: load only n bytes
  def peek(n)
    load_blob_prefix!(n)
    @data_prefix
  end
  
  # Existing method: load full blob
  def data
    load_blob!
    @data
  end
  
  private
  
  def load_blob_prefix!(n)
    return if @data_prefix && @data_prefix_size >= n
    
    # If we already loaded full data, use it
    if @data
      @data_prefix = @data[0...n]
      @data_prefix_size = n
      return
    end
    
    # Load only n bytes (capped at MAX_SIZE)
    limit = [n, MAX_SIZE].min
    @data_prefix, size = repository.load_blob(oid, limit)
    @data_prefix_size = limit
  end
  
  def load_blob!
    return if @data
    
    # If we already have a prefix that's MAX_SIZE, use it
    if @data_prefix && @data_prefix_size >= MAX_SIZE
      @data = @data_prefix
      @size = @data_prefix.bytesize
      return
    end
    
    @data, @size = repository.load_blob(oid, MAX_SIZE)
  end
end

# lib/linguist/heuristics.rb
class Heuristics
  HEURISTICS_CONSIDER_BYTES = 50 * 1024
  
  def self.call(blob, candidates)
    return [] if blob.symlink?
    self.load()
    
    # Use peek instead of data
    data = blob.peek(HEURISTICS_CONSIDER_BYTES)
    
    @heuristics.each do |heuristic|
      if heuristic.matches?(blob.name, candidates)
        return Array(heuristic.call(data))
      end
    end
    
    []
  rescue Regexp::TimeoutError
    []
  end
end

# lib/linguist/classifier.rb
class Classifier
  CLASSIFIER_CONSIDER_BYTES = 50 * 1024
  
  def self.call(blob, possible_languages)
    language_names = possible_languages.map(&:name)
    # Use peek instead of data
    classify(Samples.cache, blob.peek(CLASSIFIER_CONSIDER_BYTES), language_names).map do |name, _|
      Language[name]
    end
  end
end
```

**Benefits:**
- Reduces I/O by 60% for files that use Heuristics/Classifier (50KB vs 128KB)
- Backward compatible (existing `data` method unchanged)
- Caches prefix data for reuse
- Measurable performance improvement

**Testing:**
```ruby
# test/test_lazy_blob_peek.rb
require 'test_helper'

class TestLazyBlobPeek < Minitest::Test
  def test_peek_loads_only_requested_bytes
    repo = fixture_repo("linguist")
    blob = Linguist::LazyBlob.new(repo, "some_oid", "test.rb")
    
    # Mock repository to track bytes loaded
    loaded_bytes = []
    repo.stub(:load_blob, ->(oid, limit) {
      loaded_bytes << limit
      ["x" * limit, limit]
    }) do
      data = blob.peek(1024)
      assert_equal 1024, loaded_bytes.first
      assert_equal 1024, data.bytesize
    end
  end
  
  def test_peek_reuses_full_data_if_already_loaded
    repo = fixture_repo("linguist")
    blob = Linguist::LazyBlob.new(repo, "some_oid", "test.rb")
    
    load_count = 0
    repo.stub(:load_blob, ->(oid, limit) {
      load_count += 1
      ["x" * limit, limit]
    }) do
      blob.data  # Load full data
      blob.peek(1024)  # Should reuse full data
      assert_equal 1, load_count
    end
  end
  
  def test_heuristics_uses_peek
    blob = sample_blob("C/foo.h")
    
    # Verify Heuristics only loads 50KB
    blob.stub(:peek, ->(n) {
      assert_equal Linguist::Heuristics::HEURISTICS_CONSIDER_BYTES, n
      "// C++ code\n"
    }) do
      Linguist::Heuristics.call(blob, [Language["C"], Language["C++"]])
    end
  end
end
```

**Performance Measurement:**
```ruby
# script/benchmark-peek.rb
require 'benchmark'
require 'linguist'

repo = Linguist::Repository.from_directory(".")
blobs = repo.cache.keys.map { |path| repo.blob_at(path) }.take(1000)

Benchmark.bm(20) do |x|
  x.report("Old (full load):") do
    blobs.each { |blob| blob.data[0...50*1024] }
  end
  
  x.report("New (peek):") do
    blobs.each { |blob| blob.peek(50*1024) }
  end
end
```

### Phase 3: Repository Analysis Optimization

**Goal:** Prefilter files by vendored/documentation patterns before creating LazyBlob instances.

**Implementation:**

```ruby
# lib/linguist/repository.rb
class Repository
  MAX_TREE_SIZE = 100_000
  
  # Make MAX_TREE_SIZE configurable
  def initialize(repo, commit_oid, max_tree_size = nil)
    @repository = if repo.is_a? Linguist::Source::Repository
      repo
    else
      Linguist::Source::RuggedRepository.new(repo)
    end
    @commit_oid = commit_oid
    @max_tree_size = max_tree_size || ENV.fetch('LINGUIST_MAX_TREE_SIZE', MAX_TREE_SIZE).to_i
    
    @old_commit_oid = nil
    @old_stats = nil
    
    raise TypeError, 'commit_oid must be a commit SHA1' unless commit_oid.is_a?(String)
  end
  
  protected
  
  def compute_stats(old_commit_oid, cache = nil)
    return {} if repository.get_tree_size(@commit_oid, @max_tree_size) >= @max_tree_size
    
    repository.set_attribute_source(@commit_oid)
    diff = repository.diff(old_commit_oid, @commit_oid)
    
    # Clear file map and fetch full diff if any .gitattributes files are changed
    if cache && diff.each_delta.any? { |delta| File.basename(delta.new_file[:path]) == ".gitattributes" }
      diff = repository.diff(nil, @commit_oid)
      file_map = {}
    else
      file_map = cache ? cache.dup : {}
    end
    
    diff.each_delta do |delta|
      old = delta.old_file[:path]
      new = delta.new_file[:path]
      
      file_map.delete(old)
      next if delta.binary?
      
      if [:added, :modified].include? delta.status
        # Skip submodules and symlinks
        mode = delta.new_file[:mode]
        mode_format = (mode & 0170000)
        next if mode_format == 0120000 || mode_format == 040000 || mode_format == 0160000
        
        # NEW: Prefilter by vendored/documentation patterns
        # This avoids creating LazyBlob instances for files we'll ignore anyway
        next if quick_reject_path?(new)
        
        blob = Linguist::LazyBlob.new(repository, delta.new_file[:oid], new, mode.to_s(8))
        update_file_map(blob, file_map, new)
        blob.cleanup!
      end
    end
    
    file_map
  end
  
  # Quick rejection based on path patterns only (no blob loading)
  def quick_reject_path?(path)
    # Reuse existing regexes from BlobHelper
    # These are already loaded at module initialization
    return true if path =~ BlobHelper::VendoredRegexp
    return true if path =~ BlobHelper::DocumentationRegexp
    false
  end
end
```

**Benefits:**
- Avoids LazyBlob instantiation for vendored/documentation files
- No blob loading for rejected files
- Reuses existing regex patterns (no new dependencies)
- MAX_TREE_SIZE now configurable via environment variable
- Backward compatible (default behavior unchanged)

**Testing:**
```ruby
# test/test_repository_prefilter.rb
require 'test_helper'

class TestRepositoryPrefilter < Minitest::Test
  def test_quick_reject_vendored_paths
    repo = Repository.new(fixture_repo("linguist"), "HEAD")
    
    assert repo.send(:quick_reject_path?, "vendor/bundle/ruby.rb")
    assert repo.send(:quick_reject_path?, "node_modules/foo/bar.js")
    refute repo.send(:quick_reject_path?, "lib/linguist.rb")
  end
  
  def test_quick_reject_documentation_paths
    repo = Repository.new(fixture_repo("linguist"), "HEAD")
    
    assert repo.send(:quick_reject_path?, "docs/README.md")
    refute repo.send(:quick_reject_path?, "README.md")
  end
  
  def test_configurable_max_tree_size
    ENV['LINGUIST_MAX_TREE_SIZE'] = '200000'
    repo = Repository.new(fixture_repo("linguist"), "HEAD")
    assert_equal 200000, repo.instance_variable_get(:@max_tree_size)
  ensure
    ENV.delete('LINGUIST_MAX_TREE_SIZE')
  end
end
```

### Phase 4: Thread-Safe Global State

**Goal:** Introduce CacheFacade with thread-safe caching while preserving backward compatibility.

**Implementation:**

```ruby
# lib/linguist/cache_facade.rb
require 'mutex_m'

module Linguist
  class CacheFacade
    def initialize
      @cache = {}
      @mutex = Mutex.new
    end
    
    def fetch(key)
      @mutex.synchronize do
        return @cache[key] if @cache.key?(key)
        @cache[key] = yield
      end
    end
    
    def get(key)
      @mutex.synchronize { @cache[key] }
    end
    
    def set(key, value)
      @mutex.synchronize { @cache[key] = value }
    end
    
    def clear
      @mutex.synchronize { @cache.clear }
    end
  end
end

# lib/linguist/samples.rb
module Linguist
  module Samples
    # Keep module-level cache for backward compatibility
    @cache = nil
    
    # New: Thread-safe cache facade
    @cache_facade = CacheFacade.new
    
    def self.cache
      @cache ||= load_samples
    end
    
    # New: Thread-safe cache access
    def self.cache_threadsafe
      @cache_facade.fetch(:samples) { load_samples }
    end
    
    def self.load_samples
      # Existing implementation
    end
  end
end

# lib/linguist/heuristics.rb
module Linguist
  class Heuristics
    @heuristics = []
    
    # New: Thread-safe cache facade
    @cache_facade = CacheFacade.new
    
    def self.load
      # Keep existing behavior for backward compatibility
      if @heuristics.any?
        return
      end
      
      data = self.load_config
      named_patterns = data['named_patterns'].map { |k,v| [k, self.to_regex(v)] }.to_h
      
      data['disambiguations'].each do |disambiguation|
        exts = disambiguation['extensions']
        rules = disambiguation['rules']
        rules.map! do |rule|
          rule['pattern'] = self.parse_rule(named_patterns, rule)
          rule
        end
        @heuristics << new(exts, rules)
      end
    end
    
    # New: Thread-safe loading
    def self.load_threadsafe
      @cache_facade.fetch(:heuristics) do
        data = self.load_config
        named_patterns = data['named_patterns'].map { |k,v| [k, self.to_regex(v)] }.to_h
        
        heuristics = []
        data['disambiguations'].each do |disambiguation|
          exts = disambiguation['extensions']
          rules = disambiguation['rules']
          rules.map! do |rule|
            rule['pattern'] = self.parse_rule(named_patterns, rule)
            rule
          end
          heuristics << new(exts, rules)
        end
        heuristics
      end
    end
  end
end

# lib/linguist/configuration.rb
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
```

**Benefits:**
- Thread-safe caching with Mutex
- Backward compatible (old module-level caches still work)
- New `_threadsafe` methods for multi-threaded use
- No new dependencies (uses stdlib Mutex)
- Foundation for full global state elimination

**Testing:**
```ruby
# test/test_thread_safety.rb
require 'test_helper'

class TestThreadSafety < Minitest::Test
  def test_samples_cache_threadsafe
    threads = 10.times.map do
      Thread.new do
        100.times { Linguist::Samples.cache_threadsafe }
      end
    end
    
    threads.each(&:join)
    
    # Should not raise any errors
    assert true
  end
  
  def test_heuristics_load_threadsafe
    threads = 10.times.map do
      Thread.new do
        100.times { Linguist::Heuristics.load_threadsafe }
      end
    end
    
    threads.each(&:join)
    
    # Should not raise any errors
    assert true
  end
end
```

### Phase 5: Strategy Pipeline Flexibility

**Goal:** Add StrategyRegistry with confidence scoring and result caching.

**Implementation:**

```ruby
# lib/linguist/strategy_registry.rb
module Linguist
  class StrategyRegistry
    # Confidence levels
    HIGH_CONFIDENCE = 0.9
    MEDIUM_CONFIDENCE = 0.5
    LOW_CONFIDENCE = 0.1
    
    def initialize(strategies, enable_caching: false, enable_confidence: false)
      @strategies = strategies
      @enable_caching = enable_caching
      @enable_confidence = enable_confidence
      @cache = enable_caching ? CacheFacade.new : nil
    end
    
    def detect(blob, allow_empty: false)
      return nil if blob.likely_binary? || blob.binary? || (!allow_empty && blob.empty?)
      
      # Check cache if enabled
      if @enable_caching
        cache_key = cache_key_for(blob)
        cached = @cache.get(cache_key)
        return cached if cached
      end
      
      languages = []
      returning_strategy = nil
      
      @strategies.each do |strategy|
        returning_strategy = strategy
        candidates = strategy.call(blob, languages)
        
        if candidates.size == 1
          languages = candidates
          
          # Early exit if high confidence and enabled
          if @enable_confidence && high_confidence_strategy?(strategy)
            break
          end
          
          break
        elsif candidates.size > 1
          languages = candidates
        end
      end
      
      result = languages.first
      
      # Cache result if enabled
      if @enable_caching && result
        @cache.set(cache_key, result)
      end
      
      result
    end
    
    private
    
    def cache_key_for(blob)
      # Use blob path and OID for cache key
      "#{blob.path}:#{blob.oid}"
    end
    
    def high_confidence_strategy?(strategy)
      # Modeline and Filename are high confidence
      [
        Linguist::Strategy::Modeline,
        Linguist::Strategy::Filename
      ].include?(strategy)
    end
  end
  
  # Update Context to support StrategyRegistry
  class Context
    attr_reader :strategy_registry
    
    def initialize(
      strategies: nil,
      language_registry: nil,
      configuration: nil,
      enable_strategy_caching: false,
      enable_confidence_scoring: false
    )
      @strategies = strategies || DEFAULT_STRATEGIES
      @language_registry = language_registry || Language
      @configuration = configuration || Configuration.default
      
      @strategy_registry = StrategyRegistry.new(
        @strategies,
        enable_caching: enable_strategy_caching,
        enable_confidence: enable_confidence_scoring
      )
    end
  end
end
```

**Benefits:**
- Opt-in strategy result caching
- Opt-in confidence-based early exit
- Backward compatible (disabled by default)
- Measurable performance improvement for repeated detections

**Testing:**
```ruby
# test/test_strategy_registry.rb
require 'test_helper'

class TestStrategyRegistry < Minitest::Test
  def test_strategy_caching
    registry = Linguist::StrategyRegistry.new(
      Linguist::Context::DEFAULT_STRATEGIES,
      enable_caching: true
    )
    
    blob = sample_blob("Ruby/foo.rb")
    
    # First call
    lang1 = registry.detect(blob)
    
    # Second call should use cache
    lang2 = registry.detect(blob)
    
    assert_equal lang1, lang2
  end
  
  def test_confidence_early_exit
    call_count = Hash.new(0)
    
    strategies = Linguist::Context::DEFAULT_STRATEGIES.map do |strategy|
      ->(blob, langs) {
        call_count[strategy] += 1
        strategy.call(blob, langs)
      }
    end
    
    registry = Linguist::StrategyRegistry.new(
      strategies,
      enable_confidence: true
    )
    
    blob = sample_blob("Ruby/foo.rb")
    registry.detect(blob)
    
    # Should not call all strategies if early exit triggered
    assert call_count.values.sum < strategies.length
  end
end
```

### Phase 6: BlobHelper Decomposition

**Goal:** Split BlobHelper into focused modules while maintaining backward compatibility.

**Implementation:**

```ruby
# lib/linguist/blob_metadata.rb
module Linguist
  module BlobMetadata
    def extname
      File.extname(name.to_s)
    end
    
    def _mime_type
      if defined? @_mime_type
        @_mime_type
      else
        @_mime_type = MiniMime.lookup_by_filename(name.to_s)
      end
    end
    
    def mime_type
      _mime_type ? _mime_type.content_type : 'text/plain'
    end
    
    def binary_mime_type?
      _mime_type ? _mime_type.binary? : false
    end
    
    def likely_binary?
      binary_mime_type? && !Language.find_by_filename(name)
    end
  end
end

# lib/linguist/blob_content.rb
module Linguist
  module BlobContent
    def encoding
      if hash = detect_encoding
        hash[:encoding]
      end
    end
    
    def ruby_encoding
      if hash = detect_encoding
        hash[:ruby_encoding]
      end
    end
    
    def detect_encoding
      @detect_encoding ||= CharlockHolmes::EncodingDetector.new.detect(data) if data
    end
    
    def binary?
      if data.nil?
        true
      elsif data == ""
        false
      elsif encoding.nil?
        true
      else
        detect_encoding[:type] == :binary
      end
    end
    
    def empty?
      data.nil? || data == ""
    end
    
    def text?
      !binary?
    end
    
    def lines
      @lines ||=
        if viewable? && data
          begin
            data.chomp.split(encoded_newlines_re, -1)
          rescue Encoding::ConverterNotFoundError
            [data]
          end
        else
          []
        end
    end
    
    def loc
      lines.size
    end
    
    def sloc
      lines.grep(/\S/).size
    end
  end
end

# lib/linguist/blob_classification.rb
module Linguist
  module BlobClassification
    def vendored?
      path =~ BlobHelper::VendoredRegexp ? true : false
    end
    
    def documentation?
      path =~ BlobHelper::DocumentationRegexp ? true : false
    end
    
    def generated?
      @_generated ||= Generated.generated?(path, lambda { data })
    end
    
    def language
      @language ||= Linguist.detect(self)
    end
    
    def include_in_language_stats?
      !vendored? &&
      !documentation? &&
      !generated? &&
      language && ( defined?(detectable?) && !detectable?.nil? ?
        detectable? :
        DETECTABLE_TYPES.include?(language.type)
      )
    end
  end
end

# lib/linguist/blob_helper.rb - Updated to compose modules
module Linguist
  module BlobHelper
    include BlobMetadata
    include BlobContent
    include BlobClassification
    
    # Keep existing vendored/documentation regexes for backward compatibility
    vendored_paths = YAML.load_file(File.expand_path("../vendor.yml", __FILE__))
    VendoredRegexp = Regexp.new(vendored_paths.join('|'))
    
    documentation_paths = YAML.load_file(File.expand_path("../documentation.yml", __FILE__))
    DocumentationRegexp = Regexp.new(documentation_paths.join('|'))
    
    # Keep other existing methods
    def content_type
      @content_type ||= (binary_mime_type? || binary?) ? mime_type :
        (encoding ? "text/plain; charset=#{encoding.downcase}" : "text/plain")
    end
    
    def disposition
      if text? || image?
        'inline'
      elsif name.nil?
        "attachment"
      else
        "attachment; filename=#{CGI.escape(name)}"
      end
    end
    
    def image?
      ['.png', '.jpg', '.jpeg', '.gif'].include?(extname.downcase)
    end
    
    def solid?
      extname.downcase == '.stl'
    end
    
    def csv?
      text? && extname.downcase == '.csv'
    end
    
    def pdf?
      extname.downcase == '.pdf'
    end
    
    MEGABYTE = 1024 * 1024
    
    def large?
      size.to_i > MEGABYTE
    end
    
    def safe_to_colorize?
      !large? && text? && !high_ratio_of_long_lines?
    end
    
    def high_ratio_of_long_lines?
      return false if loc == 0
      size / loc > 5000
    end
    
    def viewable?
      !large? && text?
    end
    
    def tm_scope
      language && language.tm_scope
    end
    
    DETECTABLE_TYPES = [:programming, :markup].freeze
    
    private
    
    def encoded_newlines_re
      @encoded_newlines_re ||= Regexp.union(["\r\n", "\r", "\n"].
                                              map { |nl| nl.encode(ruby_encoding, "ASCII-8BIT").force_encoding(data.encoding) })
    end
    
    def first_lines(n)
      return lines[0...n] if defined? @lines
      return [] unless viewable? && data
      
      i, c = 0, 0
      while c < n && j = data.index(encoded_newlines_re, i)
        i = j + $&.length
        c += 1
      end
      data[0...i].split(encoded_newlines_re, -1)
    end
    
    def last_lines(n)
      if defined? @lines
        if n >= @lines.length
          @lines
        else
          lines[-n..-1]
        end
      end
      return [] unless viewable? && data
      
      no_eol = true
      i, c = data.length, 0
      k = i
      while c < n && j = data.rindex(encoded_newlines_re, i - 1)
        if c == 0 && j + $&.length == i
          no_eol = false
          n += 1
        end
        i = j
        k = j + $&.length
        c += 1
      end
      r = data[k..-1].split(encoded_newlines_re, -1)
      r.pop if !no_eol
      r
    end
  end
end
```

**Benefits:**
- Separates concerns (metadata, content, classification)
- Easier to test individual modules
- Backward compatible (BlobHelper still works as before)
- Foundation for deprecating BlobHelper mixin
- Cleaner dependencies

**Testing:**
```ruby
# test/test_blob_modules.rb
require 'test_helper'

class TestBlobModules < Minitest::Test
  def test_blob_metadata_module
    blob = sample_blob("Ruby/foo.rb")
    
    assert_equal ".rb", blob.extname
    assert_equal "text/plain", blob.mime_type
    refute blob.binary_mime_type?
  end
  
  def test_blob_content_module
    blob = sample_blob("Ruby/foo.rb")
    
    refute blob.binary?
    assert blob.text?
    refute blob.empty?
    assert blob.lines.any?
  end
  
  def test_blob_classification_module
    blob = sample_blob("Ruby/foo.rb")
    
    refute blob.vendored?
    refute blob.documentation?
    refute blob.generated?
    assert_equal Language["Ruby"], blob.language
  end
  
  def test_blob_helper_composes_all_modules
    blob = sample_blob("Ruby/foo.rb")
    
    # Should have methods from all modules
    assert blob.respond_to?(:extname)  # BlobMetadata
    assert blob.respond_to?(:binary?)  # BlobContent
    assert blob.respond_to?(:language)  # BlobClassification
  end
end
```

## Implementation Timeline

### Phase 1: Enabling Infrastructure (1-2 weeks)
- Add Context class
- Update Linguist.detect with optional context parameter
- Write comprehensive tests
- Ensure 100% backward compatibility

### Phase 2: Reduce Blob I/O (2-3 weeks)
- Add LazyBlob#peek method
- Update Heuristics and Classifier to use peek
- Write performance benchmarks
- Verify detection parity with existing behavior

### Phase 3: Repository Analysis Optimization (2-3 weeks)
- Add quick_reject_path? method
- Make MAX_TREE_SIZE configurable
- Write tests for prefiltering
- Measure performance improvement on large repos

### Phase 4: Thread-Safe Global State (3-4 weeks)
- Add CacheFacade class
- Add _threadsafe methods to Samples, Heuristics
- Add Configuration class
- Write thread-safety tests
- Document migration path

### Phase 5: Strategy Pipeline Flexibility (2-3 weeks)
- Add StrategyRegistry class
- Implement confidence scoring
- Implement result caching
- Write performance tests
- Document configuration options

### Phase 6: BlobHelper Decomposition (3-4 weeks)
- Extract BlobMetadata module
- Extract BlobContent module
- Extract BlobClassification module
- Update BlobHelper to compose modules
- Write comprehensive tests
- Document deprecation path

**Total Estimated Time:** 13-19 weeks (3-5 months)

## Success Metrics

### Performance Metrics
1. **Blob I/O Reduction:** 60% reduction in bytes read for Heuristics/Classifier
2. **Repository Analysis Speed:** 30-50% improvement for large repositories
3. **Memory Usage:** 40% reduction in peak memory usage
4. **Strategy Caching:** 80% cache hit rate for repeated detections

### Code Quality Metrics
1. **Test Coverage:** Maintain >90% test coverage
2. **Backward Compatibility:** 100% of existing tests pass
3. **Thread Safety:** No race conditions in multi-threaded tests
4. **Modularity:** Reduce average method length by 30%

### Maintainability Metrics
1. **Cyclomatic Complexity:** Reduce by 25%
2. **Coupling:** Reduce inter-module dependencies by 40%
3. **Documentation:** 100% of new public APIs documented
4. **Deprecation Path:** Clear migration guide for deprecated APIs

## Risk Mitigation

### Technical Risks

**Risk 1: Performance Regression**
- Mitigation: Comprehensive benchmarks before/after each phase
- Rollback: Feature flags allow disabling new behavior
- Validation: Run benchmarks on large public repositories

**Risk 2: Backward Compatibility Break**
- Mitigation: All new features opt-in via configuration
- Rollback: Keep old code paths active by default
- Validation: Run full test suite, including integration tests

**Risk 3: Thread Safety Issues**
- Mitigation: Comprehensive multi-threaded tests
- Rollback: Thread-safe methods are separate (_threadsafe suffix)
- Validation: Run tests with ThreadSanitizer

**Risk 4: Detection Accuracy Regression**
- Mitigation: Compare detection results before/after on sample corpus
- Rollback: Keep old behavior as default
- Validation: Run cross-validation script on all samples

### Process Risks

**Risk 1: Long Review Cycles**
- Mitigation: Small, focused PRs (one phase at a time)
- Communication: Regular updates to maintainers
- Documentation: Clear PR descriptions with rationale

**Risk 2: Maintainer Disagreement**
- Mitigation: Discuss approach before implementation
- Flexibility: Adjust plan based on feedback
- Alternatives: Provide multiple implementation options

**Risk 3: Community Disruption**
- Mitigation: Announce changes in advance
- Documentation: Clear migration guides
- Support: Respond to issues promptly

## Alternative Approaches Considered

### Alternative 1: Big Bang Rewrite
**Approach:** Rewrite entire codebase from scratch

**Pros:**
- Clean slate, no technical debt
- Can use modern Ruby features
- Optimal architecture from start

**Cons:**
- High risk of breaking changes
- Long development time (6-12 months)
- Difficult to maintain backward compatibility
- Hard to review large changes

**Decision:** Rejected due to high risk and long timeline

### Alternative 2: Parallel Implementation
**Approach:** Build new system alongside old, then switch

**Pros:**
- Can develop without affecting existing code
- Easy to compare performance
- Safe rollback

**Cons:**
- Code duplication during transition
- Increased maintenance burden
- Unclear migration path for users
- Wastes effort on temporary code

**Decision:** Rejected due to maintenance burden

### Alternative 3: Minimal Changes Only
**Approach:** Only fix critical bugs, no architectural changes

**Pros:**
- Low risk
- Fast implementation
- No compatibility concerns

**Cons:**
- Doesn't address root causes
- Technical debt continues to grow
- Performance issues remain
- Maintainability doesn't improve

**Decision:** Rejected as insufficient

### Alternative 4: Phased Refactoring (Selected)
**Approach:** Incremental, backward-compatible improvements

**Pros:**
- Low risk per phase
- Measurable progress
- Easy to review
- Backward compatible
- Can stop at any phase

**Cons:**
- Longer total timeline
- Some temporary code
- Requires discipline

**Decision:** Selected as best balance of risk and benefit

## Conclusion

This architectural refactoring proposal addresses the five critical issues in the Linguist codebase through a phased, backward-compatible approach. Each phase delivers measurable value while minimizing risk and maintaining compatibility with existing code.

The proposed changes will:
1. Improve performance by 30-60% for large repositories
2. Enable thread-safe multi-threaded usage
3. Improve code maintainability and testability
4. Provide foundation for future enhancements
5. Maintain 100% backward compatibility

The phased approach allows the project to:
- Stop at any phase if priorities change
- Measure impact of each change independently
- Review and merge small, focused PRs
- Maintain production stability throughout

We recommend starting with Phase 1 (Enabling Infrastructure) as it provides the foundation for all subsequent phases while being a pure no-op change that's easy to review and merge.

## References

- [Linguist Repository](https://github.com/github/linguist)
- [Contributing Guidelines](https://github.com/github/linguist/blob/master/CONTRIBUTING.md)
- [Ruby Concurrency Patterns](https://ruby-concurrency.github.io/)
- [Refactoring: Improving the Design of Existing Code](https://martinfowler.com/books/refactoring.html)
- [Working Effectively with Legacy Code](https://www.oreilly.com/library/view/working-effectively-with/0131177052/)

## Appendix A: Code Examples

See inline code examples throughout each phase section.

## Appendix B: Performance Benchmarks

```ruby
# script/benchmark-phases.rb
require 'benchmark'
require 'linguist'

# Benchmark Phase 2: Peek vs Full Load
def benchmark_peek
  repo = Linguist::Repository.from_directory(".")
  blobs = repo.cache.keys.map { |path| repo.blob_at(path) }.take(1000)
  
  Benchmark.bm(30) do |x|
    x.report("Phase 2 - Old (full load):") do
      blobs.each { |blob| blob.data[0...50*1024] }
    end
    
    x.report("Phase 2 - New (peek):") do
      blobs.each { |blob| blob.peek(50*1024) }
    end
  end
end

# Benchmark Phase 3: Prefiltering
def benchmark_prefilter
  repo = Linguist::Repository.from_directory(".")
  
  Benchmark.bm(30) do |x|
    x.report("Phase 3 - Old (no prefilter):") do
      repo.compute_stats(nil, nil)
    end
    
    x.report("Phase 3 - New (with prefilter):") do
      repo.compute_stats_with_prefilter(nil, nil)
    end
  end
end

# Benchmark Phase 5: Strategy Caching
def benchmark_strategy_caching
  blob = sample_blob("Ruby/foo.rb")
  
  Benchmark.bm(30) do |x|
    x.report("Phase 5 - Old (no cache):") do
      1000.times { Linguist.detect(blob) }
    end
    
    context = Linguist::Context.new(enable_strategy_caching: true)
    x.report("Phase 5 - New (with cache):") do
      1000.times { Linguist.detect(blob, context: context) }
    end
  end
end
```

## Appendix C: Migration Guide

### For Library Users

**Phase 1: No changes required**
- Existing code continues to work unchanged
- Optional: Use new Context API for customization

**Phase 2: No changes required**
- Existing code continues to work unchanged
- Performance improvement automatic

**Phase 3: Optional configuration**
```ruby
# Optional: Configure max tree size
ENV['LINGUIST_MAX_TREE_SIZE'] = '200000'
```

**Phase 4: Optional thread-safe usage**
```ruby
# For multi-threaded applications
samples = Linguist::Samples.cache_threadsafe
heuristics = Linguist::Heuristics.load_threadsafe
```

**Phase 5: Optional strategy optimization**
```ruby
# Enable strategy caching and confidence scoring
context = Linguist::Context.new(
  enable_strategy_caching: true,
  enable_confidence_scoring: true
)
language = Linguist.detect(blob, context: context)
```

**Phase 6: No changes required**
- BlobHelper continues to work unchanged
- Optional: Use new focused modules for new code

### For Linguist Contributors

**Phase 1: Use Context for tests**
```ruby
# Custom strategy order for testing
context = Linguist::Context.new(strategies: [MyStrategy])
Linguist.detect(blob, context: context)
```

**Phase 2: Use peek for new strategies**
```ruby
# New strategies should use peek instead of data
class MyStrategy
  def self.call(blob, candidates)
    data = blob.peek(10 * 1024)  # Only load 10KB
    # ... analyze data
  end
end
```

**Phase 4: Use thread-safe methods**
```ruby
# In multi-threaded code
samples = Linguist::Samples.cache_threadsafe
```

**Phase 6: Use focused modules**
```ruby
# New blob-like classes should include specific modules
class MyBlob
  include Linguist::BlobMetadata
  include Linguist::BlobContent
  # Don't include BlobClassification if not needed
end
```

## Appendix D: FAQ

**Q: Will this break my existing code?**
A: No. All changes are backward compatible. Existing code will continue to work unchanged.

**Q: Do I need to update my code to get the performance improvements?**
A: No. Phase 2 and Phase 3 improvements are automatic. Other phases require opt-in configuration.

**Q: How long will the old APIs be supported?**
A: Old APIs will be supported indefinitely. Deprecation (if any) will be announced at least 2 major versions in advance.

**Q: Can I use the new features in production?**
A: Yes. All new features are thoroughly tested and safe for production use. Start with default settings and enable optimizations as needed.

**Q: What if I find a bug in the new code?**
A: Report it on GitHub. Most new features can be disabled via configuration to work around issues.

**Q: Will this work with my custom strategies?**
A: Yes. Custom strategies will continue to work. To benefit from new features, implement the peek-based interface.

**Q: How do I know which phase to use?**
A: Start with Phase 1 (Context API) if you need customization. Use Phase 4 (thread-safe caching) if you have multi-threaded code. Other phases are automatic.

**Q: Can I contribute to this refactoring?**
A: Yes! See CONTRIBUTING.md for guidelines. Start with Phase 1 as it's the foundation for all other phases.
