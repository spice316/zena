require File.join(File.dirname(__FILE__), 'testhelp')

class HelperTest
  testfile :relations #, :basic
  def test_single
    do_test('relations', 'tags')
    #do_test('basic', 'node_path')
  end
  make_tests
end