require_relative "./helper"

class TestRepositoryPrefilter < Minitest::Test
  include Linguist

  def setup
    @repo = Repository.allocate
  end

  def test_quick_reject_path_rejects_vendor_directories
    assert @repo.send(:quick_reject_path?, "vendor/bundle/ruby/file.rb")
    assert @repo.send(:quick_reject_path?, "vendor/assets/javascripts/file.js")
    assert @repo.send(:quick_reject_path?, "Vendor/lib/file.rb")
  end

  def test_quick_reject_path_rejects_node_modules
    assert @repo.send(:quick_reject_path?, "node_modules/express/index.js")
    assert @repo.send(:quick_reject_path?, "node_modules/package/file.js")
    assert @repo.send(:quick_reject_path?, "NODE_MODULES/file.js")
  end

  def test_quick_reject_path_rejects_bower_components
    assert @repo.send(:quick_reject_path?, "bower_components/jquery/jquery.js")
    assert @repo.send(:quick_reject_path?, "bower_components/package/file.js")
  end

  def test_quick_reject_path_rejects_third_party
    assert @repo.send(:quick_reject_path?, "third_party/lib/file.rb")
    assert @repo.send(:quick_reject_path?, "third-party/lib/file.rb")
    assert @repo.send(:quick_reject_path?, "thirdparty/lib/file.rb")
  end

  def test_quick_reject_path_rejects_docs_directories
    assert @repo.send(:quick_reject_path?, "docs/api/index.md")
    assert @repo.send(:quick_reject_path?, "doc/README.md")
    assert @repo.send(:quick_reject_path?, "documentation/guide.md")
    assert @repo.send(:quick_reject_path?, "Docs/file.md")
  end

  def test_quick_reject_path_rejects_nested_vendor
    assert @repo.send(:quick_reject_path?, "lib/vendor/file.rb")
    assert @repo.send(:quick_reject_path?, "src/node_modules/file.js")
    assert @repo.send(:quick_reject_path?, "app/bower_components/file.js")
  end

  def test_quick_reject_path_accepts_normal_paths
    refute @repo.send(:quick_reject_path?, "lib/linguist/repository.rb")
    refute @repo.send(:quick_reject_path?, "src/main.js")
    refute @repo.send(:quick_reject_path?, "app/models/user.rb")
    refute @repo.send(:quick_reject_path?, "test/test_helper.rb")
  end

  def test_quick_reject_path_accepts_paths_with_vendor_in_filename
    refute @repo.send(:quick_reject_path?, "lib/vendor_helper.rb")
    refute @repo.send(:quick_reject_path?, "src/vendor.js")
    refute @repo.send(:quick_reject_path?, "app/vendored_file.rb")
  end

  def test_max_tree_size_default
    assert_equal 100_000, Repository::MAX_TREE_SIZE
  end

  def test_max_tree_size_from_env
    old_value = ENV['LINGUIST_MAX_TREE_SIZE']
    begin
      ENV['LINGUIST_MAX_TREE_SIZE'] = '50000'
      # Need to reload the constant
      Repository.send(:remove_const, :MAX_TREE_SIZE)
      load 'linguist/repository.rb'
      assert_equal 50_000, Repository::MAX_TREE_SIZE
    ensure
      # Restore original value
      if old_value
        ENV['LINGUIST_MAX_TREE_SIZE'] = old_value
      else
        ENV.delete('LINGUIST_MAX_TREE_SIZE')
      end
      # Restore default
      Repository.send(:remove_const, :MAX_TREE_SIZE)
      load 'linguist/repository.rb'
    end
  end
end
