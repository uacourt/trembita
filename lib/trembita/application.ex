defmodule Trembita.Application do
  @moduledoc """
  Головний OTP додаток ЄСІКС eCourt підсистеми.
  Ініціалізує ETS сховище, KVS Mnesia схеми, BPE рушій та запускає
  HTTP сервер Bandit для обслуговування Plug-ендпойнтів.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # 1. Ініціалізація Syn для кластерного розподілу BPE
    Application.put_env(:syn, :scopes, [:devices])
    _ = Application.ensure_all_started(:syn)
    try do
      :syn.add_node_to_scopes([:devices])
    rescue
      _ -> :ok
    end

    # 2. Ініціалізація KVS сховища та схем
    Application.put_env(:kvs, :schema, [:kvs, BPE.Metainfo])
    Application.put_env(:kvs, :dba, :kvs_mnesia)
    try do
      :kvs_mnesia.initialize()
      :kvs.join()
    rescue
      _ -> :ok
    end

    # 3. Запуск BPE процесного рушія
    _ = Application.ensure_all_started(:bpe)

    # 4. Ініціалізація ETS таблиць замість Redis (ETS instead of Redis)
    Trembita.ETSCache.init_tables()

    # 5. Дерево супервізії: запуск Bandit на основі чистого Plug
    port = Application.get_env(:trembita, :port, 4000)
    children = [
      {Bandit, plug: Trembita.Web.Router, scheme: :http, port: port}
    ]

    opts = [strategy: :one_for_one, name: Trembita.Supervisor]
    Logger.info("Starting Trembita ESICS eCourt subsystem on Bandit port #{port}...")
    Supervisor.start_link(children, opts)
  end
end

