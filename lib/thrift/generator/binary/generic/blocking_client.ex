defmodule Thrift.Generator.Binary.Generic.BlockingClient do
  alias Thrift.Generator.{
    Service
  }
  # alias Thrift.Parser.FileGroup
  alias Thrift.Protocol.Binary

  def generate(service_module, service, file_group) do
    # thrift_root = generate_thrift_root(service_module, service, file_group)

    methods = Enum.map(
      service.functions,
      &(generate_method(service_module, &1, file_group))
    )

    quote do
      defmodule Binary.Generic.BlockingClient do
        alias Thrift.Protocol.Binary

        unquote_splicing(methods)
      end
    end
  end

  def generate_method(_service_module, {func_name, function_ast}, _file_group) do

    # function_name = nil
    function_args = Enum.map(function_ast.params, &Macro.var(&1.name, nil))
    args_module = Service.module_name(function_ast, :args)
    args_binary_module = Module.concat(args_module, :BinaryProtocol)
    response_module = Service.module_name(function_ast, :response)
    response_binary_module = Module.concat(response_module, :BinaryProtocol)
    s_func_name = Atom.to_string(func_name)

    assignments =
      function_ast.params
      |> Enum.zip(function_args)
      |> Enum.map(fn {param, var} ->
        quote do
          {unquote(param.name), unquote(var)}
        end
      end)

    quote do
      def unquote(func_name)(unquote_splicing(function_args), transport) do
        args = %unquote(args_module){unquote_splicing(assignments)}
        serialized_args = unquote(args_binary_module).serialize(args)
        header = Binary.serialize(:message_begin, {:call, 0, unquote(s_func_name)})
        payload = [header | serialized_args] |> IO.iodata_to_binary()

        with(
          {:transport, response} <- transport.(payload) |> case do
            {:ok, resp} -> {:transport, resp}
            {:error, e} -> {:error, {:transport, e}}
          end,
          {:service, reply} <- Binary.deserialize(:message_begin, response.body) |> case do
            {:ok, {:reply, 0, unquote(s_func_name), reply}} -> {:service, reply}
            {:ok, {:exception, 0, unquote(s_func_name), exception}} -> {:error, {:service, Binary.deserialize(:application_exception, exception)}, response}
          end,
          {:result, result} <- unquote(response_binary_module).deserialize(reply) |> case do
            {%{success: nil} = r, _tail} when map_size(r) > 2 ->
              case Map.from_struct(r) |> Enum.find_value(fn {_, value} -> value end) do
                nil -> {:result, :ok}
                other -> {:error, {:exception, other}, response}
              end
            {%{success: res}, _tail} -> {:result, res}
          end
        ) do
          {:ok, result, response}
        end
      end
    end
  end

end
