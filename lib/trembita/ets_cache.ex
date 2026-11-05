defmodule Trembita.ETSCache do
  @moduledoc """
  Високопродуктивний in-memory шар на базі Erlang Term Storage (ETS)
  як пряма нативна альтернатива Redis (ETS instead of Redis).

  Забезпечує:
  - Zero-latency доступ до активних судових справ без мережевого оверхеду
  - Контроль ідемпотентності протоколів Нацполіції
  - Зберігання процесуальних таймерів (5 днів Дії, 15 днів судді)
  - Стан фонових OCR / ШІ генерацій
  """

  @cases_table :ecourt_cases
  @idempotency_table :idempotency_keys
  @timers_table :bpe_timers
  @ai_jobs_table :ai_jobs
  @feedback_table :ai_feedback_metrics

  def init_tables do
    create_table(@cases_table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    create_table(@idempotency_table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    create_table(@timers_table, [:ordered_set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    create_table(@ai_jobs_table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    create_table(@feedback_table, [:duplicate_bag, :public, :named_table, read_concurrency: true, write_concurrency: true])
    :ok
  end

  defp create_table(name, opts) do
    case :ets.info(name) do
      :undefined -> :ets.new(name, opts)
      _ -> name
    end
  end

  # --- Case Storage (ETS instead of Redis hashes) ---

  def put_case(case_id, case_data) when is_binary(case_id) and is_map(case_data) do
    :ets.insert(@cases_table, {case_id, Map.put(case_data, :updated_at, DateTime.utc_now())})
    :ok
  end

  def get_case(case_id) when is_binary(case_id) do
    case :ets.lookup(@cases_table, case_id) do
      [{^case_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  def update_case(case_id, updater_fun) when is_binary(case_id) and is_function(updater_fun, 1) do
    case get_case(case_id) do
      {:ok, current} ->
        updated = updater_fun.(current)
        put_case(case_id, updated)
        {:ok, updated}
      error -> error
    end
  end

  def all_cases do
    :ets.tab2list(@cases_table)
    |> Enum.map(fn {_id, data} -> data end)
  end

  # --- Idempotency & Deduplication (ETS instead of Redis SETNX / EXPIRE) ---

  def check_and_set_protocol(series, number, case_id) do
    key = {to_string(series), to_string(number)}
    case :ets.lookup(@idempotency_table, key) do
      [{^key, existing_case_id, registered_at}] ->
        {:duplicate, existing_case_id, registered_at}

      [] ->
        :ets.insert(@idempotency_table, {key, case_id, DateTime.utc_now()})
        :new
    end
  end

  # --- Procedural Timers (5 days Diia, 15 days Judge) ---

  def set_timer(case_id, type, days) do
    deadline = DateTime.utc_now() |> DateTime.add(days * 86_400, :second)
    :ets.insert(@timers_table, {{case_id, type}, deadline, DateTime.utc_now()})
    {:ok, deadline}
  end

  def get_timer(case_id, type) do
    case :ets.lookup(@timers_table, {case_id, type}) do
      [{{^case_id, ^type}, deadline, created_at}] ->
        {:ok, %{deadline: deadline, created_at: created_at, expired?: DateTime.compare(DateTime.utc_now(), deadline) == :gt}}
      [] -> {:error, :not_found}
    end
  end

  # --- AI Job State ---

  def put_ai_job(job_id, job_data) do
    :ets.insert(@ai_jobs_table, {job_id, job_data})
    :ok
  end

  def get_ai_job(job_id) do
    case :ets.lookup(@ai_jobs_table, job_id) do
      [{^job_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  # --- ML Feedback Metrics ---

  def record_ai_feedback(record) do
    :ets.insert(@feedback_table, {:feedback, record, DateTime.utc_now()})
    :ok
  end

  def get_all_feedback do
    :ets.lookup(@feedback_table, :feedback)
    |> Enum.map(fn {:feedback, rec, ts} -> Map.put(rec, :recorded_at, ts) end)
  end
end

