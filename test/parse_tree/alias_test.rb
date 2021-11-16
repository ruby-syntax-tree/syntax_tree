# frozen_string_literal: true

require 'test_helper'

class ParseTree < Ripper
  class AliasTest < Minitest::Test
    def test_alias
      assert_node(Alias, 'alias foo bar')
    end

    def test_var_alias
      assert_node(VarAlias, 'alias $foo $bar')
    end

    def test_fixtures
      assert_fixtures("alias.rb")
    end
  end
end
