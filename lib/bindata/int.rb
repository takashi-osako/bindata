require 'bindata/base_primitive'

module BinData
  # Defines a number of classes that contain an integer.  The integer
  # is defined by endian, signedness and number of bytes.

  module Int #:nodoc: all
    class << self
      def define_class(nbits, endian, signed)
        name = class_name(nbits, endian, signed)
        unless BinData.const_defined?(name)
          BinData.module_eval <<-END
            class #{name} < BinData::BasePrimitive
              register_self
              Int.define_methods(self, #{nbits}, :#{endian}, :#{signed})
            end
          END
        end

        BinData.const_get(name)
      end

      def class_name(nbits, endian, signed)
        endian_str = (endian == :big) ? "be" : "le"
        base = (signed == :signed) ? "Int" : "Uint"

        "#{base}#{nbits}#{endian_str}"
      end

      def define_methods(int_class, nbits, endian, signed)
        raise "nbits must be divisible by 8" unless (nbits % 8).zero?

        int_class.module_eval <<-END
          def assign(val)
            #{create_clamp_code(nbits, signed)}
            super(val)
          end

          def do_num_bytes
            #{nbits / 8}
          end

          #---------------
          private

          def sensible_default
            0
          end

          def value_to_binary_string(val)
            #{create_clamp_code(nbits, signed)}
            #{create_int2uint_code(nbits) if signed == :signed}
            #{create_to_binary_s_code(nbits, endian)}
          end

          def read_and_return_value(io)
            val = #{create_read_code(nbits, endian)}
            #{create_uint2int_code(nbits) if signed == :signed}
            val
          end
        END
      end

      #-------------
      private

      def create_clamp_code(nbits, signed)
        if signed == :signed
          max = (1 << (nbits - 1)) - 1
          min = -(max + 1)
        else
          min = 0
          max = (1 << nbits) - 1
        end

        "val = (val < #{min}) ? #{min} : (val > #{max}) ? #{max} : val"
      end

      def create_int2uint_code(nbits)
        "val = val & #{(1 << nbits) - 1}"
      end

      def create_uint2int_code(nbits)
        mask = (1 << (nbits - 1)) - 1

        "val = -(((~val) & #{mask}) + 1) if (val >= #{1 << (nbits - 1)})"
      end

      def create_read_code(nbits, endian)
        bits_per_word = bytes_per_word(nbits) * 8
        nwords        = nbits / bits_per_word
        nbytes        = nbits / 8

        idx = (0 ... nwords).to_a
        idx.reverse! if (endian == :big)

        parts = (0 ... nwords).collect do |i|
                  if i.zero?
                    "a.at(#{idx[i]})"
                  else
                    "(a.at(#{idx[i]}) << #{bits_per_word * i})"
                  end
                end

        unpack_str = "a = io.readbytes(#{nbytes}).unpack('#{pack_directive(nbits, endian)}')"
        assemble_str = parts.join(" + ")

        "(#{unpack_str}; #{assemble_str})"
      end

      def create_to_binary_s_code(nbits, endian)
        # special case 8bit integers for speed
        return "val.chr" if nbits == 8

        bits_per_word = bytes_per_word(nbits) * 8
        nwords        = nbits / bits_per_word
        mask          = (1 << bits_per_word) - 1

        vals = (0 ... nwords).collect do |i|
                 i.zero? ? "val" : "(val >> #{bits_per_word * i})"
               end
        vals.reverse! if (endian == :big)

        parts = (0 ... nwords).collect { |i| "#{vals[i]} & #{mask}" }
        array_str = "[" + parts.join(", ") + "]"

        "#{array_str}.pack('#{pack_directive(nbits, endian)}')"
      end

      def bytes_per_word(nbits)
        (nbits % 32).zero? ? 4 : (nbits % 16).zero? ? 2 : 1
      end

      def pack_directive(nbits, endian)
        bits_per_word = bytes_per_word(nbits) * 8
        nwords        = nbits / bits_per_word

        if (nbits % 32).zero?
          d = (endian == :big) ? 'N' : 'V'
        elsif (nbits % 16).zero?
          d = (endian == :big) ? 'n' : 'v'
        else
          d = 'C'
        end

        d * nwords
      end
    end
  end


  # Unsigned 1 byte integer.
  class Uint8 < BinData::BasePrimitive
    register_self
    Int.define_methods(self, 8, :little, :unsigned)
  end

  # Signed 1 byte integer.
  class Int8 < BinData::BasePrimitive
    register_self
    Int.define_methods(self, 8, :little, :signed)
  end

  # Create classes on demand
  class << self
    alias_method :const_missing_without_int, :const_missing
    def const_missing_with_int(name)
      name = name.to_s
      mappings = {
        /^Uint(\d+)be$/ => [:big, :unsigned],
        /^Uint(\d+)le$/ => [:little, :unsigned],
        /^Int(\d+)be$/ => [:big, :signed],
        /^Int(\d+)le$/ => [:little, :signed],
      }

      mappings.each_pair do |regex, args|
        if regex =~ name
          nbits = $1.to_i
          if (nbits % 8).zero?
            return Int.define_class(nbits, *args)
          end
        end
      end

      const_missing_without_int(name)
    end
    alias_method :const_missing, :const_missing_with_int
  end
end
