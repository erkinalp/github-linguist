require 'charlock_holmes'

module Linguist
  # BlobContent handles content analysis operations
  #
  # This module provides methods for analyzing blob content such as
  # encoding detection, binary detection, line counting, and text processing.
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

    # Try to guess the encoding
    #
    # Returns: a Hash, with :encoding, :confidence, :type
    #          this will return nil if an error occurred during detection or
    #          no valid encoding could be found
    def detect_encoding
      @detect_encoding ||= CharlockHolmes::EncodingDetector.new.detect(data) if data
    end

    # Public: Is the blob binary?
    #
    # Return true or false
    def binary?
      # Large blobs aren't even loaded into memory
      if data.nil?
        true

      # Treat blank files as text
      elsif data == ""
        false

      # Charlock doesn't know what to think
      elsif encoding.nil?
        true

      # If Charlock says its binary
      else
        detect_encoding[:type] == :binary
      end
    end

    # Public: Is the blob empty?
    #
    # Return true or false
    def empty?
      data.nil? || data == ""
    end

    # Public: Is the blob text?
    #
    # Return true or false
    def text?
      !binary?
    end

    # Public: Is the blob safe to colorize?
    #
    # Return true or false
    def safe_to_colorize?
      !large? && text? && !high_ratio_of_long_lines?
    end

    # Internal: Does the blob have a ratio of long lines?
    #
    # Return true or false
    def high_ratio_of_long_lines?
      return false if loc == 0
      size / loc > 5000
    end

    # Public: Is the blob viewable?
    #
    # Non-viewable blobs will just show a "View Raw" link
    #
    # Return true or false
    def viewable?
      !large? && text?
    end

    # Public: Get each line of data
    #
    # Requires Blob#data
    #
    # Returns an Array of lines
    def lines
      @lines ||=
        if viewable? && data
          # `data` is usually encoded as ASCII-8BIT even when the content has
          # been detected as a different encoding. However, we are not allowed
          # to change the encoding of `data` because we've made the implicit
          # guarantee that each entry in `lines` is encoded the same way as
          # `data`.
          #
          # Instead, we re-encode each possible newline sequence as the
          # detected encoding, then force them back to the encoding of `data`
          # (usually a binary encoding like ASCII-8BIT). This means that the
          # byte sequence will match how newlines are likely encoded in the
          # file, but we don't have to change the encoding of `data` as far as
          # Ruby is concerned. This allows us to correctly parse out each line
          # without changing the encoding of `data`, and
          # also--importantly--without having to duplicate many (potentially
          # large) strings.
          begin
            # `data` is split after having its last `\n` removed by
            # chomp (if any). This prevents the creation of an empty
            # element after the final `\n` character on POSIX files.
            data.chomp.split(encoded_newlines_re, -1)
          rescue Encoding::ConverterNotFoundError
            # The data is not splittable in the detected encoding.  Assume it's
            # one big line.
            [data]
          end
        else
          []
        end
    end

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

    # Public: Get number of lines of code
    #
    # Requires Blob#data
    #
    # Returns Integer
    def loc
      lines.size
    end

    # Public: Get number of source lines of code
    #
    # Requires Blob#data
    #
    # Returns Integer
    def sloc
      lines.grep(/\S/).size
    end
  end
end
