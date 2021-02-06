defmodule Thrift.Generator.Binary.Generic do
  # alias Thrift.AST.Function

  alias Thrift.Generator.{
    Service,
  #   Utils
  }
  alias Thrift.Parser.FileGroup

  def generate(service_module, service, file_group) do
    arg_readers = service.functions
      |> Map.values()
      |> Enum.map(&make_arg_reader(service_module, file_group, &1))

    reply_writers = service.functions
      |> Map.values()
      |> Enum.map(&make_reply_writer(service_module, file_group, &1))

    quote do
      defmodule Binary.Generic do
        alias Thrift.Protocol

        def read_call(binary) do
          case Protocol.Binary.deserialize(:message_begin, binary) do
            {:ok, {:call, seq, name, args_binary}} -> read_args(name, seq, args_binary)
            other -> other
          end
        end

        unquote_splicing(arg_readers)
        unquote_splicing(reply_writers)
      end
    end
  end

  def make_arg_reader(service_module, _file_group, function) do
    fn_name = Atom.to_string(function.name)
    args_module = Module.concat(service_module, Service.module_name(function, :args))
    # response_module = Module.concat(service_module, Service.module_name(function, :response))

    struct_matches =
      Enum.map(function.params, fn param ->
        {param.name, Macro.var(param.name, nil)}
      end)
    return_args = Enum.map(struct_matches, fn {_name, var} -> var end)

    quote do
      def read_args(unquote(fn_name), seq, binary_data) do
        case unquote(args_module).BinaryProtocol.deserialize(binary_data) do
          {%unquote(args_module){unquote_splicing(struct_matches)}, ""} ->
            {:ok, unquote(function.name), seq, unquote(return_args)}

          {parsed, extra} ->
            {:error, {:protocol_extra, extra, parsed}}
        end
      end
    end
  end

  def make_reply_writer(service_module, file_group, function) do
    response_module = Module.concat(service_module, Service.module_name(function, :response))
    fn_name = Atom.to_string(function.name)

    success_clause = case function do
      %{return_type: :void} -> quote do
          _ -> :noreply
        end
      %{} -> quote do
          reply ->
            response = %unquote(response_module){success: reply}
            {:reply, unquote(response_module).BinaryProtocol.serialize(response)}
      end
    end

    #NOTE: it MUST be flatmap
    exception_clauses = Enum.flat_map(function.exceptions, fn exc ->
      resolved = FileGroup.resolve(file_group, exc)
      dest_module = FileGroup.dest_module(file_group, resolved.type)
      error_var = Macro.var(exc.name, nil)
      field_setter = quote do: {unquote(exc.name), unquote(error_var)}

      quote do
        {:exception, {:error, %unquote(dest_module){} = unquote(error_var), _stacktrace}} ->
          response = %unquote(response_module){unquote(field_setter)}
          {:reply, unquote(response_module).BinaryProtocol.serialize(response)}
      end
    end)

    catch_clause = quote do
      {:exception, {kind, reason, stacktrace}} ->
        formatted_exception = Exception.format(kind, reason, stacktrace)
        # Logger.error("Exception not defined in thrift spec was thrown: #{formatted_exception}")

        error =
          Thrift.TApplicationException.exception(
            type: :unknown,
            message: "Server error: #{formatted_exception}"
          )
        {:server_error, Protocol.Binary.serialize(:application_exception, error)}
    end

    quote do
      def write_reply(unquote(function.name), seq, result) do
        case result do
          #NOTE: it MUST be unquote(++)
          unquote(exception_clauses ++ catch_clause ++ success_clause)
        end |> case do
          :noreply ->
            [Protocol.Binary.serialize(:message_begin, {:reply, seq, unquote(fn_name)}) | <<0>>]
          {:reply, data} ->
            [Protocol.Binary.serialize(:message_begin, {:reply, seq, unquote(fn_name)}) | data]
          {:server_error, data} ->
            [Protocol.Binary.serialize(:message_begin, {:exception, seq, unquote(fn_name)}) | data]
        end
      end
    end
  end
end
