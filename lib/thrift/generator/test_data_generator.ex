defmodule Thrift.Generator.TestDataGenerator do
  alias __MODULE__, as: TestDataGenerator
  alias Thrift.AST.{
    Exception,
    Struct,
    TEnum,
    TypeRef,
    Union
  }
  alias Thrift.Parser.FileGroup

  def generate(label, schema, full_name, struct) do
    case label do
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
    quote do
      utf8(100)
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
      let x <- unquote(subgen) do
        MapSet.new(x)
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
      unquote(dest_module).get_generator()
    end
  end

  def get_generator(%TypeRef{} = ref, file_group) do
    file_group
    |> FileGroup.resolve(ref)
    |> get_generator(file_group)
  end

  def get_generator(%Union{name: name}, file_group) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    quote do
      unquote(dest_module).get_generator()
    end
  end

  def get_generator(%Exception{name: name}, file_group) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    quote do
      unquote(dest_module).get_generator()
    end
  end

  def get_generator(%Struct{name: name}, file_group) do
    dest_module =
      FileGroup.dest_module(file_group, name)
      |> test_data_module_from_data_module

    quote do
      unquote(dest_module).get_generator()
    end
  end

  def test_data_module_from_data_module(data_module) do

    data_module
    |> Module.split()
    |> List.insert_at(0, "TestData")
    |> Module.concat()
  end

end
