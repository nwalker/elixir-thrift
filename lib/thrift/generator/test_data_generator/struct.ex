defmodule Thrift.Generator.TestDataGenerator.Struct do
  alias Thrift.Generator.TestDataGenerator
  def generate(schema, name, struct_ast) do
    file_group = schema.file_group
    test_data_module_name = TestDataGenerator.test_data_module_from_data_module(name)

    struct_fields = Enum.map(struct_ast.fields, &gen_struct_field/1)
    draw_fields = Enum.map(struct_ast.fields, &gen_draw(&1, file_group))

    quote do
      defmodule unquote(test_data_module_name) do
        use PropCheck

        def get_generator() do
          let [unquote_splicing(draw_fields)] do
            %unquote(name){unquote_splicing(struct_fields)}
          end
        end

      end
    end
  end


  def gen_struct_field(field_ast) do
    quote do
      unquote({field_ast.name, Macro.var(field_ast.name, nil)})
    end
  end

  def gen_draw(field_ast, file_group) do

    generator = TestDataGenerator.get_generator(field_ast.type, file_group)
    generator =
      if field_ast.required do
        generator
      else
        quote do
          oneof([unquote(generator), nil])
        end
      end

    quote do
      unquote(Macro.var(field_ast.name, nil)) <- unquote(generator)
    end
  end

end
