module Zena
  module Use
    module Context
      module ViewMethods

        # Dynamic resolution of the author class from the user prototype
        def self.visitor_node_proc
          Proc.new do |h, r, s|
            res = {:method => 'visitor.node', :nil => true}
            if prototype  = visitor.prototype
              res[:class] = prototype.vclass
            else
              res[:class] = VirtualClass['Node']
            end
            res
          end
        end

        include RubyLess
        safe_method :start => Proc.new {|h, r, s| {:method => 'start_node', :class => VirtualClass['Node']}}
        safe_method :visitor => User
        safe_method :visitor_node => visitor_node_proc
        safe_method :main => Proc.new {|h, r, s| {:method => '@node', :class => VirtualClass['Node']}}
        safe_method :root => Proc.new {|h, r, s| {:method => 'visitor.site.root_node', :class => VirtualClass['Project'], :nil => true}}
        safe_method :site => {:class => Site, :method => 'visitor.site'}

        # Group an array of records by key.
        def group_array(list)
          return nil if list.empty?
          groups = []
          h = {}
          list.each do |e|
            key = yield(e)
            unless group_id = h[key]
              h[key] = group_id = groups.size
              groups << []
            end
            groups[group_id] << e
          end
          groups
        end

        def sort_array(list)
          list.sort do |a,b|
            va = yield([a].flatten[0])
            vb = yield([b].flatten[0])
            if va && vb
              va <=> vb
            elsif va
              1
            elsif vb
              -1
            else
              0
            end
          end
        end

        def min_array(list)
          list.flatten.min do |a,b|
            va = yield(a)
            vb = yield(b)
            if va && vb
              va <=> vb
            elsif va
              1
            elsif vb
              -1
            else
              0
            end
          end
        end

        def max_array(list)
          list.flatten.min do |a,b|
            va = yield(a)
            vb = yield(b)
            if va && vb
              vb <=> va
            elsif vb
              1
            elsif va
              -1
            else
              0
            end
          end
        end

        # main node before ajax stuff (the one in browser url)
        def start_node
          @start_node ||= if params[:s]
            secure(Node) { Node.find_by_zip(params[:s]) }
          else
            @node
          end
        end

        # Enter page numbers context.
        #
        # ==== Parameters
        #
        # * +current+     - current page number
        # * +count+       - total number of pages
        # * +join_string+ - (optional) string to use to join page numbers
        # * +max_count+   - (optional) maximum number of pages to display
        # * +&block+      - block to yield for each page number. Receives |page_number, join_string|.
        def page_numbers(current, count, join_string = nil, max_count = nil)
          max_count ||= 10
          join_string ||= ''
          join_str = ''
          if count <= max_count
            1.upto(count) do |p|
              yield(p, join_str, p)
              join_str = join_string
            end
          else
            # only first pages (centered around current page)
            if current - (max_count/2) > 0
              max = current + (max_count/2)
            else
              max = max_count
            end

            if count > max
              finish = end_dots = max
            else
              finish = count
            end

            start  = [finish - max_count + 1,1].max
            if start > 1
              start_dots = start
            end

            start.upto(finish) do |p|
              yield(p, join_str, (p == start_dots || p == end_dots) ? '…' : p.to_s)
              join_str = join_string
            end
          end
        end
      end # ViewMethods

      module ZafuMethods
        def self.dom_id_proc
          Proc.new do |h, r, s|
            {:class => String, :method => h.node.dom_id(:code => true)}
          end
        end

        include RubyLess
        safe_method :dom_id => dom_id_proc


        def r_dom_id
          out node.dom_id
        end

        # Uses Enrollable::ZafuMethods::get_class

        # Return the node context for a given class (looks up into the hierarchy) or the
        # current node context if klass is nil.
        def node(klass = nil)
          super(klass && klass.kind_of?(VirtualClass) ? klass.real_class : klass)
        end

        # Enter a new context (<r:context find='all' select='pages'>). This is the same as '<r:pages>...</r:pages>'). It is
        # considered better style to use '<r:pages>...</r:pages>' instead of the more general '<r:context>' because the tags
        # give a clue on the context at start and end. Another way to open a context is the 'do' syntax: "<div do='pages'>...</div>".
        def r_context
          return parser_error("missing 'select' parameter") unless method = @params[:select]
          querybuilder_eval(method)
        end

        alias r_find r_context

        def r_count
          if node.list_context? && !@params[:select]
            rubyless_eval
          else
            @params[:find] = 'count'
            r_context
          end
        end

        def r_set
          @params.each do |var, code|
            var = var.to_s
            begin
              typed_string = ::RubyLess.translate(self, code)
              
              # Do we have this variable already ?
              if up_var = get_context_var('set_var', var)
                if up_var.klass != typed_string.klass
                  return parser_error("Type mismatch for var #{var}=#{code}: #{typed_string.klass} != #{up_var.klass}")
                end
                
                if typed_string.could_be_nil?
                  if !up_var.could_be_nil?
                    out "<% #{up_var} = #{typed_string} || #{up_var} %>"
                  else
                    out "<% #{up_var} = #{typed_string} %>"
                  end
                else  
                  out "<% #{up_var} = #{typed_string} %>"
                end
              else
                name = get_var_name('set_var', var)
                out "<% #{name} = #{typed_string} %>"
                set_context_var('set_var', var, RubyLess::TypedString.new(name, typed_string.opts))
              end
            rescue RubyLess::NoMethodError => err
              out parser_error(err.message, "set #{var}=#{code}")
            end
          end
          expand_with
        end

        # Group elements in a list. Use :order to specify order.
        def r_group
          return parser_error("cannot be used outside of a list") unless node.list_context?
          return parser_error("missing 'by' clause") unless key = @params[:by]

          #sort_key = @params[:sort] || 'title'
          # if node.will_be?(DataEntry) && DataEntry::NodeLinkSymbols.include?(key.to_sym)
          #   key = "#{key}_id"
          #   #sort_block = "{|e| (e.#{key} || {})[#{sort_key.to_sym.inspect}]}"
          #   group_array = "group_array(#{node}) {|e| e.#{key}}"
          # elsif node.will_be?(Node)
          #   if ['project', 'parent', 'section'].include?(key)
          #     #sort_block  = "{|e| (e.#{key} || {})[#{sort_key.to_sym.inspect}]}"
          #     group_array = "group_array(#{node}) {|e| e.#{key}_id}"
          #   end
          # end

          if %w{parent project section}.include?(key)
            key = "e.#{key}_id"
          else
            receiver = RubyLess::TypedString.new('e', :class => node.klass.first, :query => node.opts[:query])
            key = RubyLess.translate(receiver, key)
          end

          #if sort_block
          #  out "<% grp_#{list_var} = sort_array(#{group_array}) #{sort_block} %>"
          #else
          #end
          method = "group_array(#{node}) {|e| #{key}}"
          out "<% if #{var} = #{method} %>"
            open_node_context({:method => method}, :node => node.move_to(var, [node.klass], :query => node.opts[:query])) do
              if child['each_group']
                out expand_with
              else
                @var = nil
                r_each
              end
            end
          out "<% end %>"

          #if descendant('each_group')
          #  out expand_with(:group => var)
          #else
          #  @context[:group] = var
          #  r_each_group
          #end
        end

        def r_each_group
          r_each
        end
        
        def r_master_template
          if template = @context[:master_template]
            expand_if("#{var} = secure(Node) { Node.find_by_zip(#{template.zip}) }", node.move_to(var, template.vclass))
          else
            out ''
          end
        end
      end # ZafuMethods
    end # Context
  end # Use
end # Zena