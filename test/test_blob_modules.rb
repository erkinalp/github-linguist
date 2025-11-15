require_relative "./helper"

class TestBlobModules < Minitest::Test
  include Linguist

  def test_blob_metadata_module_exists
    assert defined?(BlobMetadata)
  end

  def test_blob_content_module_exists
    assert defined?(BlobContent)
  end

  def test_blob_classification_module_exists
    assert defined?(BlobClassification)
  end

  def test_blob_helper_includes_blob_metadata
    assert BlobHelper.included_modules.include?(BlobMetadata)
  end

  def test_blob_helper_includes_blob_content
    assert BlobHelper.included_modules.include?(BlobContent)
  end

  def test_blob_helper_includes_blob_classification
    assert BlobHelper.included_modules.include?(BlobClassification)
  end

  def test_blob_metadata_methods_available
    blob = sample_blob("Ruby/foo.rb")
    
    # BlobMetadata methods
    assert blob.respond_to?(:extname)
    assert blob.respond_to?(:mime_type)
    assert blob.respond_to?(:binary_mime_type?)
    assert blob.respond_to?(:content_type)
    assert blob.respond_to?(:disposition)
    assert blob.respond_to?(:image?)
    assert blob.respond_to?(:solid?)
    assert blob.respond_to?(:csv?)
    assert blob.respond_to?(:pdf?)
    assert blob.respond_to?(:large?)
  end

  def test_blob_content_methods_available
    blob = sample_blob("Ruby/foo.rb")
    
    # BlobContent methods
    assert blob.respond_to?(:encoding)
    assert blob.respond_to?(:ruby_encoding)
    assert blob.respond_to?(:detect_encoding)
    assert blob.respond_to?(:binary?)
    assert blob.respond_to?(:empty?)
    assert blob.respond_to?(:text?)
    assert blob.respond_to?(:safe_to_colorize?)
    assert blob.respond_to?(:viewable?)
    assert blob.respond_to?(:lines)
    assert blob.respond_to?(:loc)
    assert blob.respond_to?(:sloc)
  end

  def test_blob_classification_methods_available
    blob = sample_blob("Ruby/foo.rb")
    
    # BlobClassification methods
    assert blob.respond_to?(:vendored?)
    assert blob.respond_to?(:documentation?)
    assert blob.respond_to?(:generated?)
    assert blob.respond_to?(:language)
    assert blob.respond_to?(:tm_scope)
    assert blob.respond_to?(:include_in_language_stats?)
  end

  def test_blob_metadata_extname
    blob = sample_blob("Ruby/foo.rb")
    assert_equal ".rb", blob.extname
  end

  def test_blob_metadata_mime_type
    blob = sample_blob("Ruby/foo.rb")
    assert_equal "application/x-ruby", blob.mime_type
  end

  def test_blob_metadata_image
    blob = sample_blob("Ruby/foo.rb")
    refute blob.image?
  end

  def test_blob_content_text
    blob = sample_blob("Ruby/foo.rb")
    assert blob.text?
  end

  def test_blob_content_binary
    blob = sample_blob("Ruby/foo.rb")
    refute blob.binary?
  end

  def test_blob_content_lines
    blob = sample_blob("Ruby/foo.rb")
    assert blob.lines.is_a?(Array)
    assert blob.lines.size > 0
  end

  def test_blob_content_loc
    blob = sample_blob("Ruby/foo.rb")
    assert blob.loc > 0
  end

  def test_blob_classification_language
    blob = sample_blob("Ruby/foo.rb")
    assert_equal Language["Ruby"], blob.language
  end

  def test_blob_classification_vendored
    blob = sample_blob("Ruby/foo.rb")
    refute blob.vendored?
  end

  def test_blob_classification_documentation
    blob = sample_blob("Ruby/foo.rb")
    refute blob.documentation?
  end

  def test_blob_classification_include_in_language_stats
    blob = sample_blob("Ruby/foo.rb")
    assert blob.include_in_language_stats?
  end

  def test_backward_compatibility_all_methods_work
    blob = sample_blob("Ruby/foo.rb")
    
    # Test a mix of methods from all three modules
    assert_equal ".rb", blob.extname
    assert blob.text?
    assert_equal Language["Ruby"], blob.language
    assert blob.lines.size > 0
    assert_equal "application/x-ruby", blob.mime_type
    refute blob.vendored?
  end

  def test_modules_can_be_included_independently
    # Create a test class that includes only BlobMetadata
    test_class = Class.new do
      include BlobMetadata
      
      attr_reader :name, :size
      
      def initialize(name, size)
        @name = name
        @size = size
      end
      
      # Stub methods required by BlobMetadata
      def text?; true; end
      def binary?; false; end
      def encoding; "UTF-8"; end
    end
    
    obj = test_class.new("test.rb", 100)
    assert obj.respond_to?(:extname)
    assert_equal ".rb", obj.extname
  end
end
