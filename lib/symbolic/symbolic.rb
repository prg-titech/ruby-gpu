require "set"
require_relative "input"
require_relative "../translator/command_translator"
require_relative "../types/types"
require_relative "../type_aware_array"
require_relative "../parsing"
require_relative "../ast/nodes"
require_relative "../ast/lexical_variables_enumerator"
require_relative "../config/os_configuration"

Ikra::Configuration.check_software_configuration

module Ikra
    module Symbolic
        DEFAULT_BLOCK_SIZE = 256

        class GPUResultPointer
            attr_accessor :device_pointer

            attr_accessor :return_type

            def initialize(return_type:)
                @return_type = return_type
            end
        end

        module ParallelOperations
            def preduce(symbol: nil, **options, &block)
                if symbol == nil && block != nil
                    return ArrayReduceCommand.new(
                        to_command, 
                        block, 
                        **options)
                elsif symbol != nil && block == nil
                    block_from_symbol = eval("proc do |a, b| a.#{symbol}(b) end")
                    return ArrayReduceCommand.new(
                        to_command,
                        block_from_symbol,
                        **options)
                else
                    raise ArgumentError.new("Either block or symbol expected")
                end
            end

            def pstencil(offsets, out_of_range_value, **options, &block)
                return ArrayStencilCommand.new(
                    to_command, 
                    offsets, 
                    out_of_range_value, 
                    block, 
                    **options)
            end

            def pmap(**options, &block)
                return pcombine(
                    **options,
                    &block)
            end

            def pcombine(*others, **options, &block)
                return ArrayCombineCommand.new(
                    to_command, 
                    wrap_in_command(*others), 
                    block, 
                    **options)
            end

            def pzip(*others, **options)
                return ArrayZipCommand.new(
                    to_command, 
                    wrap_in_command(*others),
                    **options)
            end

            def +(other)
                return pcombine(other) do |a, b|
                    a + b
                end
            end

            def -(other)
                return pcombine(other) do |a, b|
                    a - b
                end
            end

            def *(other)
                return pcombine(other) do |a, b|
                    a * b
                end
            end

            def /(other)
                return pcombine(other) do |a, b|
                    a / b
                end
            end

            def |(other)
                return pcombine(other) do |a, b|
                    a | b
                end
            end

            def &(other)
                return pcombine(other) do |a, b|
                    a & b
                end
            end

            def ^(other)
                return pcombine(other) do |a, b|
                    a ^ b
                end
            end

            private

            def wrap_in_command(*others)
                return others.map do |other|
                    other.to_command
                end
            end
        end

        module ArrayCommand
            include Enumerable
            include ParallelOperations

            attr_reader :block_size

            # [Fixnum] Returns a unique ID for this command. It is used during name mangling in
            # the code generator to determine the name of array identifiers (and do other stuff?).
            attr_reader :unique_id

            # An array of commands that serve as input to this command. The number of input
            # commands depends on the type of the command.
            attr_reader :input

            # Indicates if result should be kept on the GPU for further processing.
            attr_reader :keep

            # This field can only be used if keep is true
            attr_accessor :gpu_result_pointer

            # Returns the block of the parallel section or [nil] if none.
            attr_reader :block

            @@unique_id  = 1

            def self.reset_unique_id
                @@unique_id = 1
            end

            def initialize
                super()

                # Generate unique ID
                @unique_id = @@unique_id
                @@unique_id += 1
            end

            def [](index)
                execute
                return @result[index]
            end

            def each(&block)
                next_index = 0

                while next_index < size
                    yield(self[next_index])
                    next_index += 1
                end
            end

            def pack(fmt)
                execute
                return @result.pack(fmt)
            end

            def execute
                if @result == nil
                    @result = Translator::CommandTranslator.translate_command(self).execute
                end
            end
            
            def to_command
                return self
            end

            def post_execute(environment)
                if keep
                    @gpu_result_pointer.device_pointer = environment[("prev_" + unique_id.to_s).to_sym].to_i   
                end
            end

            def has_previous_result?
                return !gpu_result_pointer.nil? && gpu_result_pointer.device_pointer != 0
            end

            # Returns a collection of the names of all block parameters.
            # @return [Array(Symbol)] list of block parameters
            def block_parameter_names
                if block != nil
                    return block.parameters.map do |param|
                        param[1]
                    end
                else
                    return []
                end
            end

            # Returns the size (number of elements) of the result, after executing the parallel 
            # section.
            # @return [Fixnum] size
            def size
                raise NotImplementedError
            end

            def target
                raise NotImplementedError
            end

            # Returns the abstract syntax tree for a parallel section.
            def block_def_node
                # TODO: add caching for AST here
                parser_local_vars = block.binding.local_variables + block_parameter_names
                source = Parsing.parse_block(block, parser_local_vars)
                return AST::BlockDefNode.new(
                    ruby_block: block,      # necessary to get binding
                    body: AST::Builder.from_parser_ast(source))
            end

            # Returns a collection of lexical variables that are accessed within a parallel 
            # section.
            # @return [Hash{Symbol => Object}]
            def lexical_externals
                all_lexical_vars = block.binding.local_variables
                lexical_vars_enumerator = AST::LexicalVariablesEnumerator.new(all_lexical_vars)
                block_def_node.accept(lexical_vars_enumerator)
                accessed_variables = lexical_vars_enumerator.lexical_variables

                result = Hash.new
                for var_name in accessed_variables
                    result[var_name] = block.binding.local_variable_get(var_name)
                end

                return result
            end

            # Returns a collection of external objects that are accessed within a parallel section.
            def externals
                return lexical_externals.keys
            end
        end

        class ArrayNewCommand
            include ArrayCommand
            
            def initialize(size, block, block_size: DEFAULT_BLOCK_SIZE, keep: false)
                super()

                @size = size
                @block = block
                @block_size = block_size
                @keep = keep

                # No input
                @input = []
            end
            
            def size
                return @size
            end
        end

        class ArrayCombineCommand
            include ArrayCommand

            def initialize(target, others, block, block_size: DEFAULT_BLOCK_SIZE, keep: false)
                super()

                @block = block
                @block_size = block_size
                @keep = keep

                # Read array at position `tid`
                @input = [SingleInput.new(command: target.to_command, pattern: :tid)] + others.map do |other|
                    SingleInput.new(command: other.to_command, pattern: :tid)
                end
            end
            
            def size
                return input.first.command.size
            end
        end

        class ArrayZipCommand
            include ArrayCommand

            def initialize(target, others, **options)
                super()

                if options.size  > 0
                    raise ArgumentError.new("Invalid options: #{options}")
                end

                @input = [SingleInput.new(command: target.to_command, pattern: :tid)] + others.map do |other|
                    SingleInput.new(command: other.to_command, pattern: :tid)
                end
            end

            def size
                return input.first.command.size
            end
        end

        class ArrayReduceCommand
            include ArrayCommand

            def initialize(target, block, block_size: DEFAULT_BLOCK_SIZE)
                super()

                @block = block
                @block_size = block_size

                @input = [ReduceInput.new(command: target.to_command, pattern: :entire)]
                @keep = keep
            end

            def execute
                if input.first.command.size == 0
                    @result = [nil]
                elsif @input.first.command.size == 1
                    @result = [input.first.command[0]]
                else
                    @result = super
                end
            end
            
            def size
                input.first.command.size
            end
        end

        class ArrayStencilCommand
            include ArrayCommand

            attr_reader :offsets
            attr_reader :out_of_range_value
            attr_reader :use_parameter_array

            def initialize(target, offsets, out_of_range_value, block, block_size: DEFAULT_BLOCK_SIZE, keep: false, use_parameter_array: true)
                super()

                # Read more than just one element, fall back to `:entire` for now

                @offsets = offsets
                @out_of_range_value = out_of_range_value
                @block = block
                @block_size = block_size
                @use_parameter_array = use_parameter_array
                @keep = keep

                if use_parameter_array
                    @input = [StencilArrayInput.new(
                        command: target.to_command,
                        pattern: :entire,
                        offsets: offsets,
                        out_of_bounds_value: out_of_range_value)]
                else
                    @input = [StencilSingleInput.new(
                        command: target.to_command,
                        pattern: :entire,
                        offsets: offsets,
                        out_of_bounds_value: out_of_range_value)]
                end
            end

            def size
                return input.first.command.size
            end

            def min_offset
                return offsets.min
            end

            def max_offset
                return offsets.max
            end
        end

        class ArraySelectCommand
            include ArrayCommand

            def initialize(target, block)
                super()

                @block = block

                # One element per thread
                @input = [SingleInput.new(command: target.to_command, pattern: :tid)]
            end
            
            # how to implement SELECT?
            # idea: two return values (actual value and boolean indicator as struct type)
        end

        class ArrayIdentityCommand
            include ArrayCommand
            
            attr_reader :target

            @@unique_id = 1

            def initialize(target, block_size: DEFAULT_BLOCK_SIZE)
                super()

                # Ensure that base array cannot be modified
                target.freeze

                # One thread per array element
                @input = [SingleInput.new(command: target, pattern: :tid)]

                @block_size = block_size
            end
            
            def execute
                return input.first.command
            end
            
            def size
                return input.first.command.size
            end

            # Returns a collection of external objects that are accessed within a parallel section. This includes all elements of the base array.
            def externals
                lexical_externals.keys + input.first.command
            end

            def base_type
                # TODO: add caching (`input` is frozen)
                type = Types::UnionType.new

                input.first.command.each do |element|
                    type.add(element.class.to_ikra_type)
                end

                return type
            end
        end
    end
end

class Array
    include Ikra::Symbolic::ParallelOperations

    class << self
        def pnew(size, **options, &block)
            return Ikra::Symbolic::ArrayNewCommand.new(size, block, **options)
        end
    end
    
    # Have to keep the old methods around because sometimes we want to have the original code
    alias_method :old_plus, :+
    alias_method :old_minus, :-
    alias_method :old_mul, :*
    alias_method :old_or, :|
    alias_method :old_and, :&

    def +(other)
        if other.is_a?(Ikra::Symbolic::ArrayCommand)
            super(other)
        else
            return self.old_plus(other)
        end
    end

    def -(other)
        if other.is_a?(Ikra::Symbolic::ArrayCommand)
            super(other)
        else
            return self.old_minus(other)
        end
    end
    
    def *(other)
        if other.is_a?(Ikra::Symbolic::ArrayCommand)
            super(other)
        else
            return self.old_mul(other)
        end
    end

    def |(other)
        if other.is_a?(Ikra::Symbolic::ArrayCommand)
            super(other)
        else
            return self.old_or(other)
        end
    end

    def &(other)
        if other.is_a?(Ikra::Symbolic::ArrayCommand)
            super(other)
        else
            return self.old_and(other)
        end
    end

    def to_command
        return Ikra::Symbolic::ArrayIdentityCommand.new(self)
    end
end

