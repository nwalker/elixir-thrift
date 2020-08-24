defmodule Thrift.Generator.Binary.Framed.Server.HTTP do
  alias Thrift.Generator.{
    Service
  }
  alias Thrift.Parser.FileGroup

  def generate(service_module, service, file_group) do
    thrift_root = generate_thrift_root(service_module, service, file_group)

    quote do
      defmodule Binary.Framed.Server.HTTP do
        unquote(thrift_root)

        def get_child_spec(module_handler) do
          {Plug.Cowboy,
           scheme: :http, plug: {__MODULE__.Router, [module_handler]}, options: [port: 4001]}
        end
      end
    end
  end

  def generate_thrift_root(service_module, service, file_group) do
    quote do
      defmodule Router do
        use Plug.Router

        alias Thrift.Protocol

        plug(:match)
        plug(:dispatch, builder_opts())

        # def init([module_handler]) do
        #   module_handler
        # end

        def init(opts) do
          IO.inspect(opts, label: "INIT OPTS")
        end

        post "/thrift" do
          # send_resp(conn, 200, "keke")
          with(
            {:ok, payload, conn} <- Plug.Conn.read_body(conn),
            {:ok, parsed} <- Protocol.Binary.deserialize(:message_begin, payload) |> IO.inspect()
          ) do
            IO.inspect(opts, label: "THRIFT OPTS")
            handle_thrift_message(conn, parsed, opts)
          end
        end

        post "/thrift/:method" do
          {:ok, payload, conn} = Plug.Conn.read_body(conn)
          conn = %{conn | body_params: payload}
          Plug.forward(conn, [method], __MODULE__.Handlers, opts)
        end

        match _ do
          send_resp(conn, 404, "not found")
        end

        def handle_thrift_message(conn, {:call, sequence_id, name, args_binary}, opts) do
          IO.inspect(args_binary, label: "args binary")
          IO.inspect(name, label: "FORWARD")
          IO.inspect(opts, label: "FORWARD opts")
          conn = %{conn | body_params: args_binary, path_info: [name]}
          Plug.forward(conn, [name], __MODULE__.Handlers, opts)
        end

        unquote(generate_thrift_handlers(service_module, service, file_group))
      end
    end
  end

  def generate_thrift_handlers(service_module, service_ast, file_group) do
    quote do
      defmodule Handlers do
        use Plug.Router

        plug(:match)
        plug(:dispatch, builder_opts())

        def init([opts]) do
          opts
        end

        unquote_splicing(Enum.map(service_ast.functions, &generate_thrift_handle(service_module, file_group, &1)))

        match _ do
          IO.inspect(conn, label: "Not matched")
          send_resp(conn, 404, "Ohh")
        end

        unquote_splicing(generate_exception_handlers(service_ast, service_module, file_group))

      end
    end
  end

  def generate_thrift_handle(service_module, file_group, {fname, function_ast}) do
    func_name = Atom.to_string(fname)
    func_path = "/" <> func_name

    handle =
      func_name
      |> Macro.underscore()
      |> String.to_atom()

    handler_args = Enum.map(function_ast.params, &Macro.var(&1.name, nil))
    args_module = Module.concat(service_module, Service.module_name(function_ast, :args))
    response_module = Module.concat(service_module, Service.module_name(function_ast, :response))

    # exception_module_root =
    #   service_module  # Calculator.Generated.Service
    #   |> Module.split()
    #   |> Enum.take_while(&(&1 != 'Service'))


    # DANGER
    # expanded into (clasue -> block) which broke with-else statement
    # need to fix on Elixir side
    #
    # generate_exception_clause =
    #   fn exception_ast ->
    #     exception_type_ast = FileGroup.resolve(file_group, exception_ast) |> IO.inspect(label: "RESOLVED")
    #     exception_module = FileGroup.dest_module(file_group, exception_type_ast.type) |> IO.inspect(label: "module")
    #     # exception_var = Macro.var(exception_ast.name, nil)
    #     # field_setter = quote do: {unquote(exception_ast.name), unquote(exception_var)}
    #     field_setter = quote do: {unquote(exception_ast.name), exc}
    #     [quote do
    #       {:exception, %unquote(exception_module){} = exc} ->
    #         response = %unquote(response_module){unquote(field_setter)}
    #         unquote(response_module).BinaryProtocol.serialize(response)
    #     end]
    # end
    #
    # exceptions_clauses = Enum.flat_map(
    #   function_ast.exceptions,
    #   generate_exception_clause
    # )
    #
    # END OF DANGER
    # # # # # #

    struct_matches =
      Enum.map(function_ast.params, fn param ->
        {param.name, Macro.var(param.name, nil)}
      end)

    quote do
      post unquote(func_path) do
        [handler_module] = opts
        IO.inspect(handler_module, label: "End of opts")
        body = conn.body_params

        encoded_response =
          with(
            {
              # %Service.AddArgs{left: left, right: right}
              %unquote(args_module){unquote_splicing(struct_matches)},
              rest
            } <-
              unquote(args_module).BinaryProtocol.deserialize(body) |> IO.inspect(label: "deser"),
            {:ok, result} <- apply(
              handler_module,
              unquote(handle),
              IO.inspect([unquote_splicing(handler_args)], label: "Args")
            ),
            response = %unquote(response_module){success: result}
          ) do
            unquote(response_module).BinaryProtocol.serialize(response)
          else
            :error -> :error
            {:exception, exc} -> handle_exc(exc, unquote(response_module))
            # unquote_splicing(exceptions_clauses)
          end

        case encoded_response do
          :error -> send_resp(conn, 500, "LOL")
          encoded_response -> send_resp(conn, 200, encoded_response)
        end

      end
    end
  end

  def generate_exception_handlers(service_ast, service_module, file_group) do
    for {_fname, function_ast} <- service_ast.functions, exception_ast <- function_ast.exceptions do
      response_module = Module.concat(service_module, Service.module_name(function_ast, :response))
      generate_exception_handler(response_module, exception_ast, file_group)
    end
  end

  def generate_exception_handler(response_module, exception_ast, file_group) do
    exception_type_ast = FileGroup.resolve(file_group, exception_ast) |> IO.inspect(label: "RESOLVED")
    exception_module = FileGroup.dest_module(file_group, exception_type_ast.type) |> IO.inspect(label: "module")
    field_setter = quote do: {unquote(exception_ast.name), exc}

    quote do
      defp handle_exc(%unquote(exception_module){} = exc, unquote(response_module)) do
        response = %unquote(response_module){unquote(field_setter)}
        unquote(response_module).BinaryProtocol.serialize(response)
      end
    end

  end
end
