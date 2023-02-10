# frozen_string_literal: true

module SyntaxTree
  module YARV
    # A sea of nodes is an intermediate representation used by a compiler to
    # represent both control and data flow in the same graph. The way we use it
    # allows us to have the vertices of the graph represent either an
    # instruction in the instruction sequence or a synthesized node that we add
    # to the graph. The edges of the graph represent either control flow or data
    # flow.
    class SeaOfNodes
      # This object represents a node in the graph that holds a YARV
      # instruction.
      class InsnNode
        attr_reader :inputs, :outputs, :insn, :offset

        def initialize(insn, offset)
          @inputs = []
          @outputs = []

          @insn = insn
          @offset = offset
        end

        def id
          offset
        end

        def label
          "%04d %s" % [offset, insn.disasm(Disassembler::Squished.new)]
        end
      end

      # Phi nodes are used to represent the merging of data flow from multiple
      # incoming blocks.
      class PhiNode
        attr_reader :inputs, :outputs, :id

        def initialize(id)
          @inputs = []
          @outputs = []
          @id = id
        end

        def label
          "#{id} φ"
        end
      end

      # Merge nodes are present in any block that has multiple incoming blocks.
      # It provides a place for Phi nodes to attach their results.
      class MergeNode
        attr_reader :inputs, :outputs, :id

        def initialize(id)
          @inputs = []
          @outputs = []
          @id = id
        end

        def label
          "#{id} ψ"
        end
      end

      # The edge of a graph represents either control flow or data flow.
      class Edge
        TYPES = %i[data control info].freeze

        attr_reader :from
        attr_reader :to
        attr_reader :type
        attr_reader :label

        def initialize(from, to, type, label)
          raise unless TYPES.include?(type)

          @from = from
          @to = to
          @type = type
          @label = label
        end
      end

      # A subgraph represents the local data and control flow of a single basic
      # block.
      class SubGraph
        attr_reader :first_fixed, :last_fixed, :inputs, :outputs

        def initialize(first_fixed, last_fixed, inputs, outputs)
          @first_fixed = first_fixed
          @last_fixed = last_fixed
          @inputs = inputs
          @outputs = outputs
        end
      end

      # The compiler is responsible for taking a data flow graph and turning it
      # into a sea of nodes.
      class Compiler
        attr_reader :dfg, :nodes

        def initialize(dfg)
          @dfg = dfg
          @nodes = []

          # We need to put a unique ID on the synthetic nodes in the graph, so
          # we keep a counter that we increment any time we create a new
          # synthetic node.
          @id_counter = 999
        end

        def compile
          local_graphs = {}
          dfg.blocks.each do |block|
            local_graphs[block.id] = create_local_graph(block)
          end

          connect_local_graphs_control(local_graphs)
          connect_local_graphs_data(local_graphs)
          cleanup_phi_nodes
          cleanup_insn_nodes

          SeaOfNodes.new(dfg, nodes, local_graphs).tap(&:verify)
        end

        private

        # Counter for synthetic nodes.
        def id_counter
          @id_counter += 1
        end

        # Create a sub-graph for a single basic block - block block argument
        # inputs and outputs will be left dangling, to be connected later.
        def create_local_graph(block)
          block_flow = dfg.block_flows.fetch(block.id)

          # A map of instructions to nodes.
          insn_nodes = {}

          # Create a node for each instruction in the block.
          block.each_with_length do |insn, offset|
            node = InsnNode.new(insn, offset)
            insn_nodes[offset] = node
            nodes << node
          end

          # The first and last node in the sub-graph, and the last fixed node.
          previous_fixed = nil
          first_fixed = nil
          last_fixed = nil

          # The merge node for the phi nodes to attach to.
          merge_node = nil

          # If there is more than one predecessor and we have basic block
          # arguments coming in, then we need a merge node for the phi nodes to
          # attach to.
          if block.incoming_blocks.size > 1 && !block_flow.in.empty?
            merge_node = MergeNode.new(id_counter)
            nodes << merge_node

            previous_fixed = merge_node
            first_fixed = merge_node
            last_fixed = merge_node
          end

          # Connect local control flow (only nodes with side effects.)
          block.each_with_length do |insn, length|
            if insn.side_effects?
              insn_node = insn_nodes[length]
              connect previous_fixed, insn_node, :control if previous_fixed
              previous_fixed = insn_node
              first_fixed ||= insn_node
              last_fixed = insn_node
            end
          end

          # Connect basic block arguments.
          inputs = {}
          outputs = {}
          block_flow.in.each do |arg|
            # Each basic block argument gets a phi node. Even if there's only
            # one predecessor! We'll tidy this up later.
            phi = PhiNode.new(id_counter)
            connect(phi, merge_node, :info) if merge_node
            nodes << phi
            inputs[arg] = phi

            block.each_with_length do |_, consumer_offset|
              consumer_flow = dfg.insn_flows[consumer_offset]
              consumer_flow.in.each_with_index do |producer, input_index|
                if producer == arg
                  connect(phi, insn_nodes[consumer_offset], :data, input_index)
                end
              end
            end

            block_flow.out.each { |out| outputs[out] = phi if out == arg }
          end

          # Connect local dataflow from consumers back to producers.
          block.each_with_length do |_, consumer_offset|
            consumer_flow = dfg.insn_flows.fetch(consumer_offset)
            consumer_flow.in.each_with_index do |producer, input_index|
              if producer.local?
                connect(
                  insn_nodes[producer.length],
                  insn_nodes[consumer_offset],
                  :data,
                  input_index
                )
              end
            end
          end

          # Connect dataflow from producers that leaves the block.
          block.each_with_length do |_, producer_pc|
            dfg
              .insn_flows
              .fetch(producer_pc)
              .out
              .each do |consumer|
                unless consumer.local?
                  # This is an argument to the successor block - not to an
                  # instruction here.
                  outputs[consumer.name] = insn_nodes[producer_pc]
                end
              end
          end

          # A graph with only side-effect free instructions will currently have
          # no fixed nodes! In that case just use the first instruction's node
          # for both first and last. But it's a bug that it'll appear in the
          # control flow path!
          SubGraph.new(
            first_fixed || insn_nodes[block.block_start],
            last_fixed || insn_nodes[block.block_start],
            inputs,
            outputs
          )
        end

        # Connect control flow that flows between basic blocks.
        def connect_local_graphs_control(local_graphs)
          dfg.blocks.each do |predecessor|
            predecessor_last = local_graphs[predecessor.id].last_fixed
            predecessor.outgoing_blocks.each_with_index do |successor, index|
              label =
                if index > 0 &&
                     index == (predecessor.outgoing_blocks.length - 1)
                  # If there are multiple outgoing blocks from this block, then
                  # the last one is a fallthrough. Otherwise it's a branch.
                  :fallthrough
                else
                  :"branch#{index}"
                end

              connect(
                predecessor_last,
                local_graphs[successor.id].first_fixed,
                :control,
                label
              )
            end
          end
        end

        # Connect data flow that flows between basic blocks.
        def connect_local_graphs_data(local_graphs)
          dfg.blocks.each do |predecessor|
            arg_outs = local_graphs[predecessor.id].outputs.values
            arg_outs.each_with_index do |arg_out, arg_n|
              predecessor.outgoing_blocks.each do |successor|
                successor_graph = local_graphs[successor.id]
                arg_in = successor_graph.inputs.values[arg_n]

                # We're connecting to a phi node, so we may need a special
                # label.
                raise unless arg_in.is_a?(PhiNode)

                label =
                  case arg_out
                  when InsnNode
                    # Instructions that go into a phi node are labelled by the
                    # offset of last instruction in the block that executed
                    # them. This way you know which value to use for the phi,
                    # based on the last instruction you executed.
                    dfg.blocks.find do |block|
                      block_start = block.block_start
                      block_end =
                        block_start + block.insns.sum(&:length) -
                          block.insns.last.length

                      if (block_start..block_end).cover?(arg_out.offset)
                        break block_end
                      end
                    end
                  when PhiNode
                    # Phi nodes to phi nodes are not labelled.
                  else
                    raise
                  end

                connect(arg_out, arg_in, :data, label)
              end
            end
          end
        end

        # We don't always build things in an optimal way. Go back and fix up
        # some mess we left. Ideally we wouldn't create these problems in the
        # first place.
        def cleanup_phi_nodes
          nodes.dup.each do |node| # dup because we're mutating
            next unless node.is_a?(PhiNode)

            if node.inputs.size == 1
              # Remove phi nodes with a single input.
              connect_over(node)
              remove(node)
            elsif node.inputs.map(&:from).uniq.size == 1
              # Remove phi nodes where all inputs are the same.
              producer_edge = node.inputs.first
              consumer_edge = node.outputs.find { |e| !e.to.is_a?(MergeNode) }
              connect(
                producer_edge.from,
                consumer_edge.to,
                :data,
                consumer_edge.label
              )
              remove(node)
            end
          end
        end

        # Eliminate as many unnecessary nodes as we can.
        def cleanup_insn_nodes
          nodes.dup.each do |node|
            next unless node.is_a?(InsnNode)

            case node.insn
            when AdjustStack
              # If there are any inputs to the adjust stack that are immediately
              # discarded, we can remove them from the input list.
              number = node.insn.number

              node.inputs.dup.each do |input_edge|
                next if input_edge.type != :data

                from = input_edge.from
                next unless from.is_a?(InsnNode)

                if from.inputs.empty? && from.outputs.size == 1
                  number -= 1
                  remove(input_edge.from)
                elsif from.insn.is_a?(Dup)
                  number -= 1
                  connect_over(from)
                  remove(from)

                  new_edge = node.inputs.last
                  new_edge.from.outputs.delete(new_edge)
                  node.inputs.delete(new_edge)
                end
              end

              if number == 0
                connect_over(node)
                remove(node)
              else
                next_node =
                  if number == 1
                    InsnNode.new(Pop.new, node.offset)
                  else
                    InsnNode.new(AdjustStack.new(number), node.offset)
                  end

                next_node.inputs.concat(node.inputs)
                next_node.outputs.concat(node.outputs)

                # Dynamically finding the index of the node in the nodes array
                # because we're mutating the array as we go.
                nodes[nodes.index(node)] = next_node
              end
            when Jump
              # When you have a jump instruction that only has one input and one
              # output, you can just connect over top of it and remove it.
              if node.inputs.size == 1 && node.outputs.size == 1
                connect_over(node)
                remove(node)
              end
            when Pop
              from = node.inputs.find { |edge| edge.type == :data }.from
              next unless from.is_a?(InsnNode)

              removed =
                if from.inputs.empty? && from.outputs.size == 1
                  remove(from)
                  true
                elsif from.insn.is_a?(Dup)
                  connect_over(from)
                  remove(from)

                  new_edge = node.inputs.last
                  new_edge.from.outputs.delete(new_edge)
                  node.inputs.delete(new_edge)
                  true
                else
                  false
                end

              if removed
                connect_over(node)
                remove(node)
              end
            end
          end
        end

        # Connect one node to another.
        def connect(from, to, type, label = nil)
          raise if from == to
          raise if !to.is_a?(PhiNode) && type == :data && label.nil?

          edge = Edge.new(from, to, type, label)
          from.outputs << edge
          to.inputs << edge
        end

        # Connect all of the inputs to all of the outputs of a node.
        def connect_over(node)
          node.inputs.each do |producer_edge|
            node.outputs.each do |consumer_edge|
              connect(
                producer_edge.from,
                consumer_edge.to,
                producer_edge.type,
                producer_edge.label
              )
            end
          end
        end

        # Remove a node from the graph.
        def remove(node)
          node.inputs.each do |producer_edge|
            producer_edge.from.outputs.reject! { |edge| edge.to == node }
          end

          node.outputs.each do |consumer_edge|
            consumer_edge.to.inputs.reject! { |edge| edge.from == node }
          end

          nodes.delete(node)
        end
      end

      attr_reader :dfg, :nodes, :local_graphs

      def initialize(dfg, nodes, local_graphs)
        @dfg = dfg
        @nodes = nodes
        @local_graphs = local_graphs
      end

      def to_mermaid
        Mermaid.flowchart do |flowchart|
          nodes.each do |node|
            flowchart.node("node_#{node.id}", node.label, shape: :rounded)
          end

          nodes.each do |producer|
            producer.outputs.each do |consumer_edge|
              label =
                if !consumer_edge.label
                  # No label.
                elsif consumer_edge.to.is_a?(PhiNode)
                  # Edges into phi nodes are labelled by the offset of the
                  # instruction going into the merge.
                  "%04d" % consumer_edge.label
                else
                  consumer_edge.label.to_s
                end

              flowchart.link(
                flowchart.fetch("node_#{producer.id}"),
                flowchart.fetch("node_#{consumer_edge.to.id}"),
                label,
                type: consumer_edge.type == :info ? :dotted : :directed,
                color: { data: :green, control: :red }[consumer_edge.type]
              )
            end
          end
        end
      end

      def verify
        # Verify edge labels.
        nodes.each do |node|
          # Not talking about phi nodes right now.
          next if node.is_a?(PhiNode)

          if node.is_a?(InsnNode) && node.insn.branch_targets.any? &&
               !node.insn.is_a?(Leave)
            # A branching node must have at least one branch edge and
            # potentially a fallthrough edge coming out.

            labels = node.outputs.map(&:label).sort
            raise if labels[0] != :branch0
            raise if labels[1] != :fallthrough && labels.size > 2
          else
            labels = node.inputs.filter { |e| e.type == :data }.map(&:label)
            next if labels.empty?

            # No nil labels
            raise if labels.any?(&:nil?)

            # Labels should start at zero.
            raise unless labels.min.zero?

            # Labels should be contiguous.
            raise unless labels.sort == (labels.min..labels.max).to_a
          end
        end
      end

      def self.compile(dfg)
        Compiler.new(dfg).compile
      end
    end
  end
end
