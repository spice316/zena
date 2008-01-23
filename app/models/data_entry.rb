=begin
A DataEntry stores unversioned information across 4 nodes. The main purpose of this data is to
store simple statistical values, registrations or other kinds of lists with nodes.

A data entry has four links to nodes (node_a, node_b, node_c, node_d) and 'nodes' (all four links). On the other side of the link, the node has four links to data sets (data_a, data_b, data_c, data_d) and 'data' (all four data sets).

The choice of four links is related to simple seizure situations that require up to four relations. For example a time invoicing utility would require 'contact' (who did the job), 'project' and 'invoice' (if billed). An accounting system would require 'from' (who paid), 'for' (budget position), 'credit' and 'debit'.

DataEntries are signed with 'creation date', 'modification date' and 'user_id'.

A visitor needs write access in all nodes the data should link to. A visitor also needs write access to the old node to remove a link to that node.
=end
class DataEntry < ActiveRecord::Base
  zafu_readable      :created_at, :updated_at, :date, :text, :node_a, :node_b, :node_c, :node_d, :nodes
  NodeLinkSymbols = [:node_a, :node_b, :node_c, :node_d]
  validate    :valid_data_entry
  before_save :sign_data
  
  
  # modify attributes so ext sees 'zip' values but we store 'ids'
  def self.transform_attributes(new_attributes)
    attributes = new_attributes.stringify_keys
    
    attributes.keys.each do |key|
      if key == 'date'
        attributes[key] = attributes[key].to_utc(_('datetime'), visitor.tz)
      elsif key =~ /^(\w+)_id$/
        if key[0..4] == 'node_'
          attributes[key] = Node.translate_pseudo_id(attributes[key],:zip) || attributes[key]
        else
          attributes[key] = Node.translate_pseudo_id(attributes[key]) || attributes[key]
        end
      elsif key == 'text'
        # translate zazen
        value = attributes[key]
        if value.kind_of?(String)
          attributes[key] = ZazenParser.new(value,:helper=>self, :node=>self).render(:parse_shortcuts=>true)
        end
      end
    end
    
    attributes
  end
  
  NodeLinkSymbols.each do |sym|
    class_eval "def #{sym}
      return nil unless self[:#{sym}_id]
      secure(Node) { Node.find_by_id(self[:#{sym}_id]) }
    end"
  end
  
  def nodes
    ids = NodeLinkSymbols.map { |s| self["#{s}_id"] }.compact.uniq
    secure(Node) { Node.find_all_by_id(ids) }
  end
  
  # Update a data entry's attributes, transforming the attributes first from the visitor's context to internal context.
  def update_attributes_with_transformation(new_attributes)
    update_attributes(DataEntrie.transform_attributes(new_attributes))
  end
  
  private
    # make sure all new/deleted node relations are allowed (write access)
    def valid_data_entry
      link_count = 0
      DataEntry::NodeLinkSymbols.each do |sym|
        sym_id = "#{sym}_id".to_sym
        link_count += 1 if self[sym_id]
        validate_node_link(sym_id)
      end
      errors.add("base", "a data entry must link to at least one node") if link_count == 0
    end
    
    # sign changes before saving
    def sign_data
      self[:user_id] = visitor[:id]
      self[:site_id] = visitor.site[:id]
    end
    
    def validate_node_link(sym)
      if new_record?
      elsif self[sym] == old[sym]
        return
      else
        # id changed
        # make sure we can write in old (need write access to remove a relation)
        begin
          secure_write(Node) { Node.find_by_id(old[sym]) } unless old[sym].nil?
        rescue ActiveRecord::RecordNotFound
          errors.add(sym, "cannot remove old relation")
        end
      end
      # check new link
      begin
        secure_write(Node) { Node.find_by_id(self[sym]) } unless self[sym].nil?
      rescue ActiveRecord::RecordNotFound
        errors.add(sym, "invalid node")
      end
    end
    
    def old
      @old ||= DataEntry.find(self[:id])
    end
end
