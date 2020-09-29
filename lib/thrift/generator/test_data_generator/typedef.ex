defmodule Thrift.Generator.TestDataGenerator.Typedef do
  alias Thrift.Generator.TestDataGenerator

  def generate(schema, name, type) do
    file_group = schema.file_group
    test_data_module_name = TestDataGenerator.test_data_module_from_data_module(name)

    quote do
      defmodule unquote(test_data_module_name) do
        use PropCheck

        def get_generator(context) when is_list(context) do
          ctx = Enum.map(context, &handler_module_from_context/1)

          f =
            TestDataGenerator.find_first_realization(
              ctx,
              {:get_generator, 1},
              &get_default_generator/1
            )

          f.(context)
        end

        def get_generator(nil) do
          get_generator([])
        end

        def get_generator(context) do
          get_generator([context])
        end

        def apply_defaults(example, nil) do
          apply_defaults(example, [])
        end

        def apply_defaults(example, context) when is_list(context) do
          ctx = Enum.map(context, &handler_module_from_context/1)

          f =
            TestDataGenerator.find_first_realization(
              context,
              {:apply_defaults, 2},
              &default_apply_defaults/2
            )

          f.(example, context)
        end

        def get_default_generator(context) do
          unquote(TestDataGenerator.get_generator(type, file_group))
        end

        def default_apply_defaults(example, context) do
        end

        def handler_module_from_context(context) do
          Module.concat(context, unquote(name))
        end
      end
    end
  end
end
