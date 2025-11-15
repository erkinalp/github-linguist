require 'linguist/generated'
require 'yaml'

module Linguist
  # BlobClassification handles language detection and classification
  #
  # This module provides methods for detecting languages, identifying
  # vendored/generated/documentation files, and determining if a blob
  # should be included in language statistics.
  module BlobClassification
    vendored_paths = YAML.load_file(File.expand_path("../vendor.yml", __FILE__))
    VendoredRegexp = Regexp.new(vendored_paths.join('|'))

    # Public: Is the blob in a vendored directory?
    #
    # Vendored files are ignored by language statistics.
    #
    # See "vendor.yml" for a list of vendored conventions that match
    # this pattern.
    #
    # Return true or false
    def vendored?
      path =~ VendoredRegexp ? true : false
    end

    documentation_paths = YAML.load_file(File.expand_path("../documentation.yml", __FILE__))
    DocumentationRegexp = Regexp.new(documentation_paths.join('|'))

    # Public: Is the blob in a documentation directory?
    #
    # Documentation files are ignored by language statistics.
    #
    # See "documentation.yml" for a list of documentation conventions that match
    # this pattern.
    #
    # Return true or false
    def documentation?
      path =~ DocumentationRegexp ? true : false
    end

    # Public: Is the blob a generated file?
    #
    # Generated source code is suppressed in diffs and is ignored by
    # language statistics.
    #
    # May load Blob#data
    #
    # Return true or false
    def generated?
      @_generated ||= Generated.generated?(path, lambda { data })
    end

    # Public: Detects the Language of the blob.
    #
    # May load Blob#data
    #
    # Returns a Language or nil if none is detected
    def language
      @language ||= Linguist.detect(self)
    end

    # Internal: Get the TextMate compatible scope for the blob
    def tm_scope
      language && language.tm_scope
    end

    DETECTABLE_TYPES = [:programming, :markup].freeze

    # Internal: Should this blob be included in repository language statistics?
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
