require "seria/version"
require 'seria/converters'

module Seria

  module InfoTable

    extend ActiveSupport::Concern

    included do
      klass_name = self.name.gsub(Seria.descriptor.camelize, '')
      belongs_to klass_name.downcase.to_sym
      alias_method :owner, klass_name.downcase.to_sym

      before_save :to_db
      attr_reader :in_memory
    end

    def convert
      converter.convert
    end

    def converters
      Seria.config.converters || {}
    end

    def converter
      (converters[field_name] ||
          converters[field_type] ||
          DefaultConverter).new(
          read_attribute(Seria.config.fields.value),
          read_attribute(Seria.config.fields.type))
    end

    def field_name
      read_attribute Seria.config.fields.key
    end

    def field_value
      convert
    end
    def field_type
      read_attribute(Seria.config.fields.type)
    end
    def field_type=(val)
      write_attribute(Seria.config.fields.type, val)
    end
    def field_value=(val)
      write_attribute(Seria.config.fields.value, val)
    end

    def to_db
      self.field_value = convert #force cast back from varchar in case not a new entry
      self.field_type = read_attribute(Seria.config.fields.value).class.to_s
      self.field_value = converter.to_db
      true
    end

    def self.define_info_table(class_name)
      unless defined?(class_name) && class_name.is_a?(Class)
        Object.const_set class_name, Class.new(ActiveRecord::Base)
      end
      klass = class_name.constantize
      klass.send(:include, Seria::InfoTable) unless klass.include? Seria::InfoTable
      if Rails.version =~ /^3/
        klass.send(:attr_accessible, *(Seria.config.fields.marshal_dump.values))
      end
    end

  end

  module InfoTableOwner

    extend ActiveSupport::Concern

    included do
      InfoTable::define_info_table class_name

      has_many class_name.tableize.to_sym, class_name: class_name, :autosave => true do

        def []= key, val
          info = lookup(key)
          if info
            info.field_value = val
            info.field_type = val.class.name
          else
            build(
                Seria.config.fields.key => key,
                Seria.config.fields.value => val,
                Seria.config.fields.type => val.class.name
            )
          end
          val
        end
        def [] key
          info = lookup(key)
          info.field_value if info
        end
        def lookup key
          to_a.select{|i| i.field_name == key.to_s}.first
        end
      end
      alias_method :my_infos, class_name.tableize.to_sym
      alias_method Seria.table_suffix.to_sym, class_name.tableize.to_sym
    end

    def method_missing(sym, *args, &block)
      if sym.to_s =~ /\=$/
        my_infos[sym.to_s[0..-2]] = args.first
      else
        info = Seria.config.perform_lookup_on_method_missing && my_infos.lookup(sym)
        info ? info.field_value : super
      end
    end

    module ClassMethods

      def class_name
        "#{self.to_s}#{Seria.descriptor.camelize}"
      end

    end

  end
end
