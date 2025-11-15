require 'linguist/blob_metadata'
require 'linguist/blob_content'
require 'linguist/blob_classification'

module Linguist
  # DEPRECATED Avoid mixing into Blob classes. Prefer functional interfaces
  # like `Linguist.detect` over `Blob#language`. Functions are much easier to
  # cache and compose.
  #
  # Avoid adding additional bloat to this module.
  #
  # BlobHelper is a mixin for Blobish classes that respond to "name",
  # "data" and "size" such as Grit::Blob.
  #
  # This module now composes three focused modules:
  # - BlobMetadata: File metadata (extensions, MIME types, etc.)
  # - BlobContent: Content analysis (encoding, binary detection, lines, etc.)
  # - BlobClassification: Language detection and classification
  module BlobHelper
    include BlobMetadata
    include BlobContent
    include BlobClassification
  end
end
