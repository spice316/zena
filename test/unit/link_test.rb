require File.dirname(__FILE__) + '/../test_helper'
class LinkDummy < ActiveRecord::Base
  acts_as_secure_node
  acts_as_multiversioned
  set_table_name 'nodes'
  link :icon, :class_name=>'Image', :unique=>true
  link :icon_for, :class_name=>'Node', :as_unique=>true, :as=>'icon'
  link :tags
  # test reverse links
  link :hot, :class_name=>'LinkDummy', :unique=>true
  link :hot_for, :class_name=>'LinkDummy', :as=>'hot', :as_unique=>true
  link :recipients, :class_name=>'LinkDummy'
  link :letters, :class_name=>'LinkDummy', :as=>'recipient'
  link :wife,    :class_name=>'LinkDummy', :unique=>true, :as_unique=>true
  link :husband, :class_name=>'LinkDummy', :unique=>true, :as=>'wife', :as_unique=>true
  def ref_field; :parent_id; end
  def version_class; DummyVersion; end
  def secure_before_validation
    @visitor = visitor
    super
  end
end

class SpecialLinkDummy < LinkDummy
  link :whatever, :class_name=>'LinkDummy'
  link :biglist,  :class_name=>'LinkDummy', :collector=>true
end

class DummyVersion < ActiveRecord::Base
  belongs_to :node, :class_name=>'LinkDummy', :foreign_key=>'node_id'
  before_validation     :version_before_validation
  set_table_name 'versions'
  
  def version_before_validation
    self[:text]    ||= ""
    self[:title]   ||= node[:name]
    self[:summary] ||= ""
    self[:comment] ||= ""
  end
end

class SuperDummy < ActiveRecord::Base
  # remove 'secure' method defined in ActiveRecord::Base
  undef_method :secure
  set_table_name 'contact_contents'
  link :employees, :class_name=>'SuperDummy'
  link :boss, :class_name=>'SuperDummy', :as=>'employee', :unique=>true
end

class LinkTest < ZenaTestUnit

  def setup
    super
    # cleanWater, status, wiki
    LinkDummy.connection.execute "UPDATE nodes SET type='LinkDummy' WHERE kpath IN ('NP', 'NPP', 'NPS')"
    # 'menu' Tag si private for tiger
    LinkDummy.connection.execute "UPDATE nodes SET inherit=0, rgroup_id=NULL, wgroup_id=NULL, pgroup_id=NULL WHERE id = '25';"
  end
  
  def test_role_links
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @node.tag_ids = [nodes_id(:art),nodes_id(:news)]
    @node.icon_id = 20
    assert @node.save, "Can save node"
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    groups = @node.role_links
    assert_equal 2, groups.size
    assert_equal 'icon', groups[0][0][:role]
    assert_equal 1, groups[0][1].size
    assert_equal 'tag', groups[1][0][:role]
    assert_equal 2, groups[1][1].size
  end
  
  def test_class_roles
    roles = SpecialLinkDummy.roles
    assert_equal 11, roles.size
  end
  
  def test_roles_for_form
    roles = SpecialLinkDummy.roles_for_form
    assert_equal 11, roles.size
    assert_equal ['tag', 'tags'], roles[roles.size-3]
  end
  
  def test_add_link_errors
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @node.tag_ids = [nodes_id(:art),nodes_id(:news)]
    assert @node.save
    assert_equal 2, @node.tags.size
    @node.add_link('tags', nodes_id(:status) )
    assert !@node.save, "Cannot save"
    assert_equal 'invalid target', @node.errors['tag']
  end
  
  def test_add_link_ok
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @node.tag_ids = [nodes_id(:art),nodes_id(:news)]
    @node.save
    assert_equal 2, @node.tags.size
    @node.add_link('tags', nodes_id(:menu) )
    assert @node.save, "Can save"
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    tags = @node.tags
    assert_equal 3, tags.size
    assert_equal 'menu', tags[2].name
  end
  
  def test_zips
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @node.tag_ids = [nodes_id(:art),nodes_id(:news)]
    @node.save
    assert_equal "#{nodes_zip(:art)}, #{nodes_zip(:news)}", @node.tag_zips
  end
  
  def test_remove_link_errors
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @node.tag_ids = [nodes_id(:menu),nodes_id(:art)]
    assert @node.save, "Can save"
    tags = @node.tags
    assert_equal 2, @node.tags.size
    assert_equal 'art', tags[0][:name]
    link_id = tags[0][:link_id]
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:cleanWater)) }
    assert_raise (ActiveRecord::RecordNotFound){ @node.remove_link( link_id ) }
  end
  

  def test_remove_link_ok
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @node.tag_ids = [nodes_id(:art),nodes_id(:news)]
    @node.save
    assert_equal 2, @node.tags.size
    tags = @node.tags(:conditions=>['name = ?', 'news'])
    assert_raise (ActiveRecord::RecordNotFound) { @node.remove_link(1) }
    @node.remove_link( tags[0][:link_id] )
    assert @node.save, "Can save"
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    tags = @node.tags
    assert_equal 1, tags.size
    assert_equal 'art', tags[0].name
  end
  
  def test_link_icon
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    assert_nil @node.icon
    @node.icon_id = 20
    assert @node.save
    assert_equal 20, @node.icon_id
    assert_kind_of Image, icon = @node.icon
    assert_equal 20, icon[:id]
    assert_equal "bird", icon.name
  end
  
  def test_link_on_create
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.create(:parent_id=>1, :name=>'lalatest', :tag_ids=>[nodes_id(:art).to_s,nodes_id(:news).to_s])}
    assert ! @node.new_record?, "Not a new record"
    assert_equal nodes_id(:art), @node.tags[0][:id]
  end
  
  def test_bad_icon
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    assert_nil @node.icon
    @node.icon_id = 'hello'
    assert_nil @node.icon
    @node.icon_id = 4 # bad class
    @node.save
    assert_equal 0, Link.find_all_by_source_id_and_role(19, 'icon').size
    @node.icon_id = 13645
    @node.save
    assert_equal 0, Link.find_all_by_source_id_and_role(19, 'icon').size
  end
  
  def test_unique_icon
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    assert_nil @node.icon
    @node.icon_id = 20
    @node.save
    assert_equal 20, @node.icon[:id]
    @node.icon_id = 21
    @node.save
    assert_equal 21, @node.icon[:id]
    assert_equal 1, Link.find_all_by_source_id_and_role(19, 'icon').size
  end
  
  def test_remove_icon
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    assert_nothing_raised { @node.icon_id = nil }
    @node.icon_id = 20
    @node.save
    assert_equal 20, @node.icon[:id]
    @node.icon_id = nil
    @node.save
    assert_nil @node.icon
    @node.icon_id = '20'
    @node.save
    assert_equal 20, @node.icon[:id]
    @node.icon_id = ''
    @node.save
    assert_nil @node.icon
  end
  
  def test_many_tags
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    assert_nothing_raised { @node.tags }
    assert_nil @node.tags
    @node.tag_ids = [nodes_id(:art),nodes_id(:news)]
    @node.save
    tags = @node.tags
    assert_equal 2, tags.size
    assert_equal 'art', tags[0].name
    assert_equal 'news', tags[1].name
    tags = @node.tags(:conditions=>"#{Node.table_name}.id <> #{nodes_id(:art)}")
    assert_equal 1, tags.size
    assert_equal 'news', tags[0].name
    @node.tag_ids = [nodes_id(:art)]
    @node.save
    tags = @node.tags
    assert_equal 1, tags.size
    assert_equal 'art', tags[0].name
  end
  
  def test_many_tags_with_direct_set
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    assert_nothing_raised { @node.tags }
    assert_nil @node.tags
    @node.tags = [nodes(:art),nodes(:news)]
    @node.save
    tags = @node.tags
    assert_equal 2, tags.size
    assert_equal 'art', tags[0].name
    assert_equal 'news', tags[1].name
    @node.tags = [nodes(:art)]
    @node.save
    tags = @node.tags
    assert_equal 1, tags.size
    assert_equal 'art', tags[0].name
  end
  
  def test_can_remove_tag
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @node.tag_ids = [nodes_id(:art),nodes_id(:news)]
    @node.save
    assert_equal 2, @node.tags.size
    @node.remove_tag(nodes_id(:art))
    @node.save
    tags = @node.tags
    assert_equal 1, tags.size
    assert_equal 'news', tags[0].name
  end

  def test_can_add_tag
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @node.add_tag(nodes_id(:news))
    @node.save
    tags = @node.tags
    assert_equal 1, tags.size
    assert_equal 'news', tags[0].name
  end
  
  def test_can_set_empty_array
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @node.tag_ids = [nodes_id(:news), nodes_id(:art)]
    @node.save
    assert_equal 2, @node.tags.size
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @node.tag_ids = []
    @node.save
    assert_nil @node.tags
  end

  def test_hot_for
    login(:lion)
    @source = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @target = secure(LinkDummy) { LinkDummy.find(nodes_id(:cleanWater)) }
    @source.hot_id = @target[:id]
    @source.save
    assert_equal @target[:name], @source.hot[:name]
    assert_equal @source[:name], @target.hot_for[0][:name]
  end
  
  def test_set_hot_for
    login(:lion)
    @source = secure(LinkDummy) { LinkDummy.find(nodes_id(:cleanWater)) }
    @target = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    @target.hot_for = [@source]
    @target.save
    assert_equal @target[:name], @source.hot[:name]
    assert_equal @source[:name], @target.hot_for[0][:name]
  end
  
  def test_hot_for_as_unique
    login(:lion)
    @source1 = secure(LinkDummy) { LinkDummy.find(nodes_id(:cleanWater)) }
    @source2 = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    @target1 = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    @target2 = secure(LinkDummy) { LinkDummy.find(nodes_id(:bananas)) }
    @source1.hot = @target1
    @source1.save
    assert_equal @target1[:name], @source1.hot[:name]
    assert_equal @source1[:name], @target1.hot_for[0][:name]
    @target2.hot_for_ids = [@source1.id, @source2.id]
    @target2.save
    assert_equal @target2[:name], @source1.hot[:name]
    assert_equal @target2[:name], @source2.hot[:name]
    assert_equal @source1[:name], @target2.hot_for[0][:name]
    @target2.hot_for = [@source1, @source2]
    @target2.save
    assert_equal @target2[:name], @source1.hot[:name]
    assert_equal @target2[:name], @source2.hot[:name]
    assert_equal @source1[:name], @target2.hot_for[0][:name]
    assert_equal 1, Link.find_all_by_source_id_and_role(@source1.id, 'hot').size
    assert_equal 2, Link.find_all_by_target_id_and_role(@target2.id, 'hot').size
  end
  
  def test_recipients_and_letters
    login(:lion)
    @source  = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki))  }
    @target1 = secure(LinkDummy) { LinkDummy.find(nodes_id(:cleanWater)) }
    @target2 = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    @source.recipient_ids = [11,12]
    @source.save
    assert_equal 2, @source.recipients.size
    assert_equal @source[:name], @target1.letters[0][:name]
    assert_equal @source[:name], @target2.letters[0][:name]
    @target1.remove_letter(nodes_id(:wiki))
    @target1.save
    assert_equal 1, @source.recipients.size
    assert_nil @target1.letters
    assert_equal @source[:name], @target2.letters[0][:name]
  end
  
  def test_cannot_remove_hidden_with_set_ids
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    @node.tag_ids = [nodes_id(:art),nodes_id(:news),nodes_id(:menu)]
    assert @node.save
    tags = @node.tag_ids
    assert_equal 3, tags.size
    assert tags.include?(nodes_id(:menu)), "Contains the private tag 'menu'"
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    tags = @node.tag_ids
    assert_equal 2, tags.size
    assert !tags.include?(nodes_id(:menu)), "Does not contain the private tag 'menu'"
    @node.tag_ids = [nodes_id(:art)]
    assert @node.save
    assert_equal 1, @node.tags.size
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    tags = @node.tag_ids
    assert_equal 2, tags.size
    assert tags.include?(nodes_id(:menu)), "Contains the private tag 'menu'"
  end
  
  def test_cannot_remove_hidden_with_remove
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    @node.tag_ids = [nodes_id(:art),nodes_id(:news),nodes_id(:menu)]
    assert @node.save
    tags = @node.tag_ids
    assert_equal 3, tags.size
    assert tags.include?(nodes_id(:menu)), "Contains the private tag 'menu'"
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    tags = @node.tag_ids
    assert_equal 2, tags.size
    assert !tags.include?(nodes_id(:menu)), "Does not contain the private tag 'menu'"
    @node.remove_tag(nodes_id(:news))
    @node.remove_tag(nodes_id(:menu))
    assert @node.save
    assert_equal 1, @node.tags.size
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    tags = @node.tag_ids
    assert_equal 2, tags.size
    assert tags.include?(nodes_id(:menu)), "Contains the private tag 'menu'"
  end
  
  def test_husband_and_wife
    login(:tiger)
    @husband  = secure(LinkDummy) { LinkDummy.find(nodes_id(:cleanWater)) }
    @wife     = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki))  }
    @husband2 = secure(LinkDummy) { LinkDummy.find(nodes_id(:status))  }
    
    @husband.wife_id = @wife.id
    assert @husband.save
    assert_equal @husband.id, @wife.husband.id
    assert_equal @wife.id, @husband.wife.id
    @wife.husband_id = @husband2.id
    @wife.save
    assert_equal @husband2.id, @wife.husband.id
    assert_equal @wife.id, @husband2.wife.id
    assert_nil @husband.wife
  end
  
  def test_husband_and_wife_with_direct_set
    login(:tiger)
    @husband  = secure(LinkDummy) { LinkDummy.find(nodes_id(:cleanWater)) }
    @wife     = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki))  }
    @husband2 = secure(LinkDummy) { LinkDummy.find(nodes_id(:status))  }

    @husband.wife = @wife
    assert @husband.save
    assert_equal @husband.id, @wife.husband.id
    assert_equal @wife.id, @husband.wife.id
    @wife.husband = @husband2
    @wife.save
    assert_equal @husband2.id, @wife.husband.id
    assert_equal @wife.id, @husband2.wife.id
    assert_nil @husband.wife
  end
  
  def test_tags_for_form
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    @node.tag_ids = [nodes_id(:art)]
    assert @node.save
    assert_equal 1, @node.tags.size
    tags_for_form = @node.tags_for_form
    assert_equal 3, tags_for_form.size
    assert tags_for_form[0][:link_id], "Art tag checked"
    assert !tags_for_form[1][:link_id], "News tag not checked"
    assert_equal 'news', tags_for_form[1][:name]
    assert_equal nodes_id(:art), tags_for_form[0][:id]
  end
  
  def test_tags_for_form_with_filter
    login(:tiger)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    @node.tag_ids = [nodes_id(:art)]
    assert @node.save
    assert_equal 1, @node.tags.size
    tags_for_form = @node.tags_for_form
    assert_equal 3, tags_for_form.size
    tags_for_form = @node.tags_for_form(:conditions=>"nodes.id IN (#{nodes_id(:art)})")
    assert_equal 1, tags_for_form.size
    assert tags_for_form[0][:link_id], "Art tag checked"
  end
  
  def test_out_of_secure
    @bob = SuperDummy.find(3)
    @joe = SuperDummy.find(4)
    @bob.employees = [@joe]
    assert @bob.save
    assert_equal @joe.id, @bob.employees[0][:id]
    assert_equal @bob.id, @joe.boss[:id]
  end
  
  def test_other_options_for_find
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:wiki)) }
    assert_nothing_raised { @node.tags }
    assert_nil @node.tags
    @node.tag_ids = [nodes_id(:art),nodes_id(:news)]
    @node.save
    tags = @node.tags(:limit=>1, :order=>'name DESC')
    assert_equal 1, tags.size
    assert_equal 'news', tags[0].name
  end
  
  def test_or_option_for_find
    LinkDummy.connection.execute "UPDATE nodes SET type='Tag', kpath='NPT' WHERE id IN (12);" # status
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:cleanWater)) }
    @node.tag_ids = [nodes_id(:art),nodes_id(:news)]
    @node.save
    @pages = secure(LinkDummy) { LinkDummy.find(:all, :conditions=>["kpath LIKE 'NPT%' AND parent_id = ?", @node[:id]]) }
    assert_equal 2, @node.tags.size
    assert_equal 1, @pages.size
    @pages_and_tags = @node.tags(:or=>["parent_id = ?", @node[:id]])
    assert_equal 3, @pages_and_tags.size
    @pages_and_tags = @node.tags(:or=>"parent_id = #{@node[:id]}")
    assert_equal 3, @pages_and_tags.size
  end
  
  def test_or_option_for_find_no_doubles
    LinkDummy.connection.execute "UPDATE nodes SET type='Tag', kpath='NPT' WHERE id IN (12);" # status
    login(:lion)
    @node = secure(LinkDummy) { LinkDummy.find(nodes_id(:cleanWater)) }
    @node.tag_ids = [nodes_id(:art),nodes_id(:status)]
    @node.save
    @pages = secure(LinkDummy) { LinkDummy.find(:all, :conditions=>["kpath LIKE 'NPT%' AND parent_id = ?", @node[:id]]) }
    assert_equal 2, @node.tags.size
    assert_equal 1, @pages.size
    @pages_and_tags = @node.tags(:or=>["parent_id = ?", @node[:id]])
    assert_equal 2, @pages_and_tags.size
  end
  
  def test_from_option
    login(:lion)
    @node1 = secure(LinkDummy) { LinkDummy.find(nodes_id(:projects)) }
    @icon1 = secure(LinkDummy) { LinkDummy.find(nodes_id(:bird_jpg)) }
    @node1.icon = @icon1
    @node1.save
    @node2 = secure(LinkDummy) { LinkDummy.find(nodes_id(:status)) }
    @icon2 = secure(LinkDummy) { LinkDummy.find(nodes_id(:flower_jpg)) }
    @node2.icon = @icon2
    @node2.save
    # reload
    @node1 = secure(LinkDummy) { LinkDummy.find(nodes_id(:projects)) }
    assert_equal nodes_id(:bird_jpg), @node1.icon[:id]
    assert_equal 2, @node1.icon_for(:from=>'project').size
  end
  
  def test_destroy
    assert false, "todo"
  end
end
