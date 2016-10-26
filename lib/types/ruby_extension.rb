require "set"
require_relative "primitive_type"
require_relative "union_type"

class Fixnum
    class << self
        def to_ikra_type
            Ikra::Types::PrimitiveType::Int
        end
        
        def _ikra_t_to_f(receiver_type)
            Ikra::Types::UnionType.create_float
        end

        def _ikra_c_to_f(receiver)
            "(float) #{receiver}"
        end

        def _ikra_t_to_i(receiver_type)
            Ikra::Types::UnionType.create_int
        end

        def _ikra_c_to_i(receiver)
            "#{receiver}"
        end
    end
end

class Float
    class << self
        def to_ikra_type
            Ikra::Types::PrimitiveType::Float
        end
        
        def _ikra_t_to_f(receiver_type)
            Ikra::Types::UnionType.create_float
        end

        def _ikra_c_to_f(receiver)
            "#{receiver}"
        end

        def _ikra_t_to_i(receiver_type)
            Ikra::Types::UnionType.create_int
        end

        def _ikra_c_to_i(receiver)
            "(int) #{receiver}"
        end
    end
end

class TrueClass
    class << self
        def to_ikra_type
            Ikra::Types::PrimitiveType::Bool
        end
    end
end

class FalseClass
    class << self
        def to_ikra_type
            Ikra::Types::PrimitiveType::Bool
        end
    end
end

module Math
    class << self
        class << self
            def _ikra_t_cos(receiver_type)
                Ikra::Types::UnionType.create_float
            end

            def _ikra_c_cos(receiver)
                "cos((float) #{receiver})"
            end

            def _ikra_t_sin(receiver_type)
                Ikra::Types::UnionType.create_float
            end

            def _ikra_c_sin(receiver)
                "sin((float) #{receiver})"
            end

            def _ikra_t_tan(receiver_type)
                Ikra::Types::UnionType.create_float
            end

            def _ikra_c_tan(receiver)
                "tan((float) #{receiver})"
            end
        end
    end
end
