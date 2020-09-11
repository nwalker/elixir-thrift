defmodule Thrift.Generator.TestDataGenerator.Union do
  alias Thrift.Generator.TestDataGenerator
  def generate(schema, name, struct_ast) do
    file_group = schema.file_group
    test_data_module_name = TestDataGenerator.test_data_module_from_data_module(name)

    subgens = Enum.map(struct_ast.fields, &gen_sub_gens(&1, file_group, name))
    fields = Enum.map(struct_ast.fields, &Macro.var(&1.name, nil))

    quote do
      defmodule unquote(test_data_module_name) do
        use PropCheck

        def get_generator() do

          unquote_splicing(subgens)

          oneof([unquote_splicing(fields)])
        end

      end
    end
  end


  def gen_sub_gens(field_ast, file_group, module_name) do
    field_var = Macro.var(field_ast.name, nil)
    gen = TestDataGenerator.get_generator(field_ast.type, file_group)
    fill_field = [{field_ast.name, field_var}]
    quote do
      unquote(field_var) =
        let unquote(field_var) <- unquote(gen) do
          %unquote(module_name){unquote_splicing(fill_field)}
        end
    end
  end

end
