defmodule Thrift.Generator.TestDataGenerator do
  alias __MODULE__, as: TestDataGenerator

  alias Thrift.AST.{
    Exception,
    Struct,
    TEnum,
    TypeRef,
    Typedef,
    Union
  }

  alias Thrift.Parser.FileGroup

  def generate(label, schema, full_name, struct) do
    case label do
      :typedef -> TestDataGenerator.Typedef.generate(schema, full_name, struct)
      :union -> TestDataGenerator.Union.generate(schema, full_name, struct)
      :enum -> TestDataGenerator.Enum.generate(schema, full_name, struct)
      _ -> TestDataGenerator.Struct.generate(schema, full_name, struct)
    end
  end

  def get_generator(:bool, _) do
    quote do
      bool()
    end
  end

  def get_generator(:string, _) do
    ascii = ?a..?z |> Enum.to_list()

    quote do
      let chars <- list(oneof(unquote(ascii))) do
        List.to_string(chars)
      end
    end
  end

  def get_generator(:binary, _) do
    quote do
      binary(100)
    end
  end

  def get_generator(:i8, _) do
    quote do
      integer(-128, 127)
    end
  end

  def get_generator(:i16, _) do
    quote do
      integer(-32_768, 32_767)
    end
  end

  def get_generator(:i32, _) do
    quote do
      integer(-2_147_483_648, 2_147_483_647)
    end
  end

  def get_generator(:i64, _) do
    quote do
      integer(
        -9_223_372_036_854_775_808,
        9_223_372_036_854_775_807
      )
    end
  end

  def get_generator(:double, _) do
    quote do
      float()
    end
  end

  def get_generator({:list, t}, file_group) do
    subgen = get_generator(t, file_group)

    quote do
      list(unquote(subgen))
    end
  end

  def get_generator({:set, t}, file_group) do
    subgen = get_generator({:list, t}, file_group)

    quote do
      let set <- unquote(subgen) do
        MapSet.new(set)
      end
    end
  end

  def get_generator({:map, {k, v}}, file_group) do
    key_subgen = get_generator(k, file_group)
    val_subgen = get_generator(v, file_group)

    quote do
      map(unquote(key_subgen), unquote(val_subgen))
    end
  end

  def get_generator(%TEnum{name: name}, file_group) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    quote do
      unquote(dest_module).get_generator(context)
    end
  end

  def get_generator(
        %TypeRef{referenced_type: type_name},
        %FileGroup{resolutions: resolutions} = file_group
      ) do
    case resolutions[type_name] do
      %Typedef{} = td ->
        get_generator(td, file_group)

      other_type ->
        file_group
        |> FileGroup.resolve(other_type)
        |> get_generator(file_group)
    end
  end

  def get_generator(%Union{name: name}, file_group) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    quote do
      unquote(dest_module).get_generator(context)
    end
  end

  def get_generator(%Exception{name: name}, file_group) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    quote do
      unquote(dest_module).get_generator(context)
    end
  end

  def get_generator(%Struct{name: name}, file_group) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    quote do
      unquote(dest_module).get_generator(context)
    end
  end

  def get_generator(%Typedef{name: name}, file_group) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    quote do
      unquote(dest_module).get_generator(context)
    end
  end

  def test_data_module_from_data_module(data_module) do
    Module.concat(TestData, data_module)
  end

  def apply_defaults(struct_) do
    apply_defaults(struct_, nil)
  end
  def apply_defaults(struct_, context) when is_struct(struct_) do
    module_name =
      struct_.__struct__
      |> test_data_module_from_data_module()

    apply(module_name, :apply_defaults, [struct_, context])
  end

  def apply_defaults(some_list, context) when is_list(some_list) do
    Enum.map(some_list, &apply_defaults(&1, context))
  end

  def apply_defaults(some_map, context) when is_map(some_map) do
    Map.new(some_map, fn {k, v} -> {k, apply_defaults(v, context)} end)
  end

  def apply_defaults(%MapSet{} = some_set, context) do
    MapSet.new(some_set, &apply_defaults(&1, context))
  end

  def apply_defaults(anything_else, _context) do
    anything_else
  end

  def find_first_realization([], _fns, default) do
    default
  end

  def find_first_realization([module | rest], {fname, arity} = func, default) do
    Code.ensure_loaded(module)

    if function_exported?(module, fname, arity) do
      Function.capture(module, fname, arity)
    else
      find_first_realization(rest, func, default)
    end
  end
end
