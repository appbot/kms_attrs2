require 'msgpack'
require 'kms_rails/core'

module KmsRails
  module ActiveRecord
    class << self
      def included base
        base.extend ClassMethods
      end
    end
    
    module ClassMethods
      def kms_attr(field, key_id:, retain: false, msgpack: false, context_key: nil, context_value: nil)
        include InstanceMethods

        real_field = "#{field}_enc"
#        raise RuntimeError, "Field '#{real_field}' must exist to store encrypted data" unless self.column_names.include?(real_field)
        raise RuntimeError, "Field '#{field}' must not be a real column, '#{real_field}' is the real column" if self.column_names.include?(field)
        
        enc = Core.new(key_id: key_id, msgpack: msgpack, context_key: context_key, context_value: context_value)

        define_method "#{field}=" do |data|
          if data.blank? # Just set to nil if nil
            clear_retained(field)
            self[real_field] = nil
            return 
          end
          if data.class == Hash
            data = data.to_json
          end
          set_retained(field, data) if retain
          encrypted_data = enc.encrypt(data)
          data = nil
          
          store_hash(field, encrypted_data)
        end

        define_method "#{real_field}" do
          Core.to64( get_hash(field) )
        end

        define_method "#{field}" do
          hash = get_hash(field)
          return nil unless hash

          if retain && (plaintext = get_retained(field))
            plaintext
          else
            plaintext = enc.decrypt(hash)
            set_retained(field, plaintext) if retain
            plaintext
          end
          begin
            plaintext = JSON.parse(plaintext)
          rescue JSON::ParserError => e
          end
          return plaintext
        end

        define_method "#{field}_clear" do
          clear_retained(field)
        end

      end
    end

    module InstanceMethods
      def store_hash(field, data)
        self["#{field}_enc"] = data.to_msgpack
      end

      def get_hash(field)
        hash = read_attribute("#{field}_enc")
        hash ? MessagePack.unpack(hash) : nil
      end

      def get_retained(field)
        @_retained ||= {}
        @_retained[field]
      end

      def set_retained(field, plaintext)
        @_retained ||= {}

        if @_retained[field]
          Core.shred_string(@_retained[field]) if @_retained[field].class == String
          @_retained[field] = nil
        end

        @_retained[field] = plaintext.dup
      end

      def clear_retained(field)
        @_retained ||= {}
        return if !@_retained.include?(field) || @_retained[field].nil?
        Core.shred_string(@_retained[field]) if @_retained[field].class == String
        @_retained[field] = nil
      end
    end
  end
end

if Object.const_defined?('ActiveRecord')
  ActiveRecord::Base.send(:include, KmsRails::ActiveRecord)
end
