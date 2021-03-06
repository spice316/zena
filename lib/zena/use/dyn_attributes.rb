=begin
Copyright (c) 2007 Gaspard Bucher

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
=end

module Zena
  module Use
    module DynAttributes
      class DynAttributeProxy
        def self.for(obj, opts={})
          self.new(obj, opts)
        end

        def initialize(obj, opts={})
          @owner   = obj
          @options = opts
        end

        def attributes=(attrs)
          attrs.each do |k,v|
            self[k] = v
          end
        end

        def would_edit?(hash)
          hash.each do |k, v|
            return true if self[k.to_s] != v && !(self[k.to_s].blank? && v.blank?)
          end
          false
        end

        def changed?
          @original != @hash
        end

        def [](key)
          return nil unless valid_key?(key)
          hash[key.to_s]
        end

        def map
          hash.map do |k,v|
            yield(k,v)
          end
        end

        def send(key)
          return nil unless valid_key?(key)
          hash[key.to_s]
        end

        # empty values are considered as nil
        def []=(key,value)
          return unless valid_key?(key)
          hash[key.to_s] = (value && value != '') ? value : nil
        end

        def keys
          hash.keys
        end

        def each
          hash.each {|e| yield(e) }
        end

        def delete(key)
          hash.delete(key.to_s)
        end

        def save
          return unless @hash
          add = []
          upd = []
          del = []
          # detect removed elements
          Hash[*@keys.map{|k,v| [k,nil]}.flatten].merge(@hash).each do |key,value|
            if !value && id = @keys[key]
              del << id
            elsif value && id = @keys[key]
              upd << [value,id]
            elsif value
              add << [key, value, @owner[:id].to_i]
            end
          end

          unless add.empty?
            Zena::Db.insert_many(table_name, %W{key value owner_id}, add)
          end

          unless del.empty?
            connection.execute "DELETE FROM #{table_name} WHERE id IN ('#{del.join("','")}')"
          end

          upd.each do |value,id|
            connection.execute "UPDATE #{table_name} SET value = #{connection.quote(value)} WHERE id = '#{id}'"
          end

          # clear hash so it will be reloaded if needed
          @hash = @original = nil
        end

        def clone_for(obj, opts={})
          # only keep the values, not the keys
          clone = DynAttributeProxy.for(obj, opts)
          # load clone's actual attributes so the keys are set
          clone_hash = clone.send(:hash)
          # replace with new one
          clone.instance_variable_set(:@hash, hash.dup)
          clone
        end

        def update_with(new_hash)
          hash # make sure current elements are loaded
          @hash = Hash[*new_hash.dup.map{|k,v| [k.to_s,v]}.flatten]
        end

        def destroy
          connection.execute "DELETE FROM #{table_name} WHERE owner_id = '#{@owner[:id].to_i}'"
        end

        def inspect
          "#<#{self.class}:#{sprintf('%x',self.object_id)}\n" +
          "@hash =\n{ " +
           ((hash || {}).sort.map do |k,v|
             sprintf("%15s => %s", k, v.inspect)
           end.join("\n  ")) + "}, @owner = #<#{@owner.class}:#{sprintf('%x',@owner.object_id)}>, @options = #{@options.inspect} >"
        end

        private
          def valid_key?(key)
            key && key != '' && (@options[:only].nil? || @options[:only].include?(key.to_sym))
          end

          def connection
            @connection ||= @owner.class.connection
          end

          def table_name
            @options[:table_name]
          end

          def hash
            @hash ||= begin
              if @owner.new_record?
                @hash = {}
                @keys = {}
              else
                sql = "SELECT id,key,value FROM #{table_name} WHERE owner_id = '#{@owner[:id].to_i}'"
                @hash = {}
                @keys = {}
                rows = connection.select_all(sql, "#{table_name} Load").map! do |record|
                  @hash[record['key']] = record['value']
                  @keys[record['key']] = record['id'].to_i
                end
              end
              @original = @hash.dup
              @hash
            end
          end

      end # DynAttributeProxy

      module ClassMethods
        # Look at Zena::Acts::DynAttribute for documentation.
        def dynamic_attributes_setup(opts={})
          options = {:table_name => 'dyn_attributes'}.merge(opts)
          if nested_alias = options.delete(:nested_alias)
            include Zena::Use::NestedAttributesAlias::ModelMethods
            nested_attributes_alias nested_alias
          end

          # This is used by Sphinx brick or other 'rails association crawlers'.
          self.has_many :dynamic_attributes, :foreign_key => 'owner_id', :table_name => options[:table_name], :class_name => 'DynAttribute'

          class_eval <<-END
            def self.dyn_attribute_options
              #{options.inspect}
            end
          END
        end
      end # ClassMethods

      module ModelMethods
        # this is called when the module is included into the 'base' module
        def self.included(base)
          # add all methods from the module "AddActsAsMethod" to the 'base' module
          base.extend  Zena::Use::DynAttributes::ClassMethods

          # This is used by Sphinx brick or other 'rails association crawlers'.
          base.has_many      :dynamic_attributes, :foreign_key => 'owner_id', :table_name => 'dyn_attributes', :class_name => 'DynAttribute'
          base.after_save    :save_dynamic_attributes
          base.after_destroy :destroy_attributes
          base.class_eval <<-END
            def self.dyn_attribute_options
              {:table_name => 'dyn_attributes'}
            end
          END
        end

        public

        def dyn
          @dyn_attributes ||= DynAttributeProxy.for(self, self.class.dyn_attribute_options)
        end

        def dyn=(dyn_attributes)
          if dyn_attributes.kind_of?(DynAttributeProxy)
            @dyn_attributes = dyn_attributes.clone_for(self, self.class.dyn_attribute_options)
          else
            dyn.update_with(dyn_attributes)
          end
        end

        def dyn_attributes=(attributes)
          dyn.attributes = attributes
        end

        private
          def save_dynamic_attributes
            @dyn_attributes.save if @dyn_attributes
            true # continue callbacks
          end

          def destroy_attributes
            dyn.destroy
          end

          def method_missing(sym,*args)
            if sym.to_s =~ /^d_(.*?)(=|)$/
              if $2 == '='
                # set
                self.prop[$1] = args[0]
              else
                # get
                self.prop[$1]
              end
            else
              super
            end
          end
      end # ModelMethods
    end # DynAttributes
  end # Use
end # Zena