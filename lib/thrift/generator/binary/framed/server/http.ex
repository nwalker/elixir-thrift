defmodule Thrift.Generator.Binary.Framed.Server.HTTP do
  alias Thrift.Generator.{
    Service,
  }
  def generate(service_module, service, file_group) do

    thrift_root = generate_thrift_root(service_module, service)

    quote do
      defmodule Binary.Framed.Server.HTTP do

        unquote(thrift_root)

        def get_child_spec(module_handler) do
          {Plug.Cowboy, scheme: :http, plug: {__MODULE__.Router, [module_handler]}, options: [port: 4001]}
        end
      end
    end
  end

  def generate_thrift_root(service_module, service) do
    quote do
      defmodule Router do
        use Plug.Router

        alias Thrift.Protocol

        plug :match
        plug :dispatch, builder_opts()

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

        match _ do
          send_resp(conn, 404, "not found")
        end

        def handle_thrift_message(conn, {:call, sequence_id, name, args_binary}, opts) do
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

        plug :match
        plug :dispatch

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

    struct_matches =
      Enum.map(function_ast.params, fn param ->
        {param.name, Macro.var(param.name, nil)}
      end)
    quote do
      post unquote(func_path) do
        with(
          {:ok, body, conn} <- Plug.Conn.read_body(conn),
          {
            %unquote(args_module){unquote_splicing(struct_matches)},  # %Service.AddArgs{left: left, right: right}
            rest
          } <- unquote(args_module).BinaryProtocol.deserialize(body)
        ) do
          
        end
        send_resp(conn, 200, unquote(fname) <> "GOTCHA" <> inspect(opts))
      end
    end

  end
end
