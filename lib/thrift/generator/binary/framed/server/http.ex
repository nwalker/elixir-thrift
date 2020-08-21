defmodule Thrift.Generator.Binary.Framed.Server.HTTP do
  alias Thrift.Generator.{
    Service
  }

  def generate(service_module, service, file_group) do
    thrift_root = generate_thrift_root(service_module, service)

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

  def generate_thrift_root(service_module, service) do
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

        unquote(generate_thrift_handlers(service_module, service))
      end
    end
  end

  def generate_thrift_handlers(service_module, service) do
    quote do
      defmodule Handlers do
        use Plug.Router

        plug(:match)
        plug(:dispatch, builder_opts())

        def init([opts]) do
          opts
        end

        unquote_splicing(Enum.map(service.functions, &generate_thrift_handle(service_module, &1)))

        match _ do
          IO.inspect(conn, label: "Not matched")
          send_resp(conn, 404, "Ohh")
        end
      end
    end
  end

  def generate_thrift_handle(service_module, {fname, function_ast}) do
    func_name = Atom.to_string(fname)
    func_path = "/" <> func_name

    handle =
      func_name
      |> Macro.underscore()
      |> String.to_atom()

    handler_args = Enum.map(function_ast.params, &Macro.var(&1.name, nil))
    args_module = Module.concat(service_module, Service.module_name(function_ast, :args))
    response_module = Module.concat(service_module, Service.module_name(function_ast, :response))

    # |> IO.inspect(label: "body"),
    struct_matches =
      Enum.map(function_ast.params, fn param ->
        {param.name, Macro.var(param.name, nil)}
      end)

    quote do
      post unquote(func_path) do
        [handler_module] = opts
        IO.inspect(handler_module, label: "End of opts")
        body = conn.body_params

        result =
          with(
            {
              # %Service.AddArgs{left: left, right: right}
              %unquote(args_module){unquote_splicing(struct_matches)},
              rest
            } <-
              unquote(args_module).BinaryProtocol.deserialize(body) |> IO.inspect(label: "deser")
          ) do
            apply(
              handler_module,
              unquote(handle),
              IO.inspect([unquote_splicing(handler_args)], label: "Args")
            )
          end

        case result do
          {:ok, result} -> nil
        end

        IO.inspect(result)
        response = %unquote(response_module){success: result}
        IO.inspect(response)
        encoded_result = unquote(response_module).BinaryProtocol.serialize(response)
        send_resp(conn, 200, encoded_result)
      end
    end
  end
end
