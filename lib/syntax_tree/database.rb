# frozen_string_literal: true

module SyntaxTree
  # Provides the ability to index source files into a database, then query for
  # the nodes.
  module Database
    class IndexingVisitor < SyntaxTree::FieldVisitor
      attr_reader :database, :filepath, :node_id

      def initialize(database, filepath)
        @database = database
        @filepath = filepath
        @node_id = nil
      end

      private

      def comments(node)
      end

      def field(name, value)
        return unless value.is_a?(SyntaxTree::Node)

        binds = [node_id, visit(value), name]
        database.execute(<<~SQL, binds)
          INSERT INTO edges (from_id, to_id, name)
          VALUES (?, ?, ?)
        SQL
      end

      def list(name, values)
        values.each_with_index do |value, index|
          binds = [node_id, visit(value), name, index]
          database.execute(<<~SQL, binds)
            INSERT INTO edges (from_id, to_id, name, list_index)
            VALUES (?, ?, ?, ?)
          SQL
        end
      end

      def node(node, _name)
        previous = node_id
        binds = [
          node.class.name.delete_prefix("SyntaxTree::"),
          filepath,
          node.location.start_line,
          node.location.start_column
        ]

        database.execute(<<~SQL, binds)
          INSERT INTO nodes (type, path, line, column)
          VALUES (?, ?, ?, ?)
        SQL

        begin
          @node_id = database.last_insert_row_id
          yield
          @node_id
        ensure
          @node_id = previous
        end
      end

      def text(name, value)
      end

      def pairs(name, values)
        values.each_with_index do |(key, value), index|
          binds = [node_id, visit(key), "#{name}[0]", index]
          database.execute(<<~SQL, binds)
            INSERT INTO edges (from_id, to_id, name, list_index)
            VALUES (?, ?, ?, ?)
          SQL

          binds = [node_id, visit(value), "#{name}[1]", index]
          database.execute(<<~SQL, binds)
            INSERT INTO edges (from_id, to_id, name, list_index)
            VALUES (?, ?, ?, ?)
          SQL
        end
      end
    end

    # Query for a specific type of node.
    class TypeQuery
      attr_reader :type

      def initialize(type)
        @type = type
      end

      def each(database, &block)
        sql = "SELECT * FROM nodes WHERE type = ?"
        database.execute(sql, type).each(&block)
      end
    end

    # Query for the attributes of a node, optionally also filtering by type.
    class AttrQuery
      attr_reader :type, :attrs

      def initialize(type, attrs)
        @type = type
        @attrs = attrs
      end

      def each(database, &block)
        joins = []
        binds = []

        attrs.each do |name, query|
          ids = query.each(database).map { |row| row[0] }
          joins << <<~SQL
            JOIN edges AS #{name}
            ON #{name}.from_id = nodes.id
            AND #{name}.name = ?
            AND #{name}.to_id IN (#{(["?"] * ids.size).join(", ")})
          SQL

          binds.push(name).concat(ids)
        end

        sql = +"SELECT nodes.* FROM nodes, edges #{joins.join(" ")}"

        if type
          sql << " WHERE nodes.type = ?"
          binds << type
        end

        sql << " GROUP BY nodes.id"
        database.execute(sql, binds).each(&block)
      end
    end

    # Query for the results of either query.
    class OrQuery
      attr_reader :left, :right

      def initialize(left, right)
        @left = left
        @right = right
      end

      def each(database, &block)
        left.each(database, &block)
        right.each(database, &block)
      end
    end

    # A lazy query result.
    class QueryResult
      attr_reader :database, :query

      def initialize(database, query)
        @database = database
        @query = query
      end

      def each(&block)
        return enum_for(__method__) unless block_given?
        query.each(database, &block)
      end
    end

    # A pattern matching expression that will be compiled into a query.
    class Pattern
      class CompilationError < StandardError
      end

      attr_reader :query

      def initialize(query)
        @query = query
      end

      def compile
        program =
          begin
            SyntaxTree.parse("case nil\nin #{query}\nend")
          rescue Parser::ParseError
            raise CompilationError, query
          end

        compile_node(program.statements.body.first.consequent.pattern)
      end

      private

      def compile_error(node)
        raise CompilationError, PP.pp(node, +"").chomp
      end

      # Shortcut for combining two queries into one that returns the results of
      # if either query matches.
      def combine_or(left, right)
        OrQuery.new(left, right)
      end

      # in foo | bar
      def compile_binary(node)
        compile_error(node) if node.operator != :|

        combine_or(compile_node(node.left), compile_node(node.right))
      end

      # in Ident
      def compile_const(node)
        value = node.value

        if SyntaxTree.const_defined?(value, false)
          clazz = SyntaxTree.const_get(value)
          TypeQuery.new(clazz.name.delete_prefix("SyntaxTree::"))
        else
          compile_error(node)
        end
      end

      # in SyntaxTree::Ident
      def compile_const_path_ref(node)
        parent = node.parent
        if !parent.is_a?(SyntaxTree::VarRef) ||
             !parent.value.is_a?(SyntaxTree::Const)
          compile_error(node)
        end

        if parent.value.value == "SyntaxTree"
          compile_node(node.constant)
        else
          compile_error(node)
        end
      end

      # in Ident[value: String]
      def compile_hshptn(node)
        compile_error(node) unless node.keyword_rest.nil?

        attrs = {}
        node.keywords.each do |keyword, value|
          compile_error(node) unless keyword.is_a?(SyntaxTree::Label)
          attrs[keyword.value.chomp(":")] = compile_node(value)
        end

        type = node.constant ? compile_node(node.constant).type : nil
        AttrQuery.new(type, attrs)
      end

      # in Foo
      def compile_var_ref(node)
        value = node.value

        if value.is_a?(SyntaxTree::Const)
          compile_node(value)
        else
          compile_error(node)
        end
      end

      def compile_node(node)
        case node
        when SyntaxTree::Binary
          compile_binary(node)
        when SyntaxTree::Const
          compile_const(node)
        when SyntaxTree::ConstPathRef
          compile_const_path_ref(node)
        when SyntaxTree::HshPtn
          compile_hshptn(node)
        when SyntaxTree::VarRef
          compile_var_ref(node)
        else
          compile_error(node)
        end
      end
    end

    class Connection
      attr_reader :raw_connection

      def initialize(raw_connection)
        @raw_connection = raw_connection
      end

      def execute(query, binds = [])
        raw_connection.execute(query, binds)
      end

      def index_file(filepath)
        program = SyntaxTree.parse(SyntaxTree.read(filepath))
        program.accept(IndexingVisitor.new(self, filepath))
      end

      def last_insert_row_id
        raw_connection.last_insert_row_id
      end

      def prepare
        raw_connection.execute(<<~SQL)
          CREATE TABLE nodes (
            id integer primary key,
            type varchar(20),
            path varchar(200),
            line integer,
            column integer
          );
        SQL

        raw_connection.execute(<<~SQL)
          CREATE INDEX nodes_type ON nodes (type);
        SQL

        raw_connection.execute(<<~SQL)
          CREATE TABLE edges (
            id integer primary key,
            from_id integer,
            to_id integer,
            name varchar(20),
            list_index integer
          );
        SQL

        raw_connection.execute(<<~SQL)
          CREATE INDEX edges_name ON edges (name);
        SQL
      end

      def search(query)
        QueryResult.new(self, Pattern.new(query).compile)
      end
    end
  end
end
