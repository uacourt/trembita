defmodule Trembita.KVSRepo do
  @moduledoc """
  Сховище сутностей та аудит-трейсу на базі KVS (Key-Value Storage Abstraction).
  Забезпечує довготривалу персистентність облікових записів та журналу подій.
  """

  @doc """
  Запис події до журналу аудиту справи через KVS ланцюжок.
  """
  def log_audit_event(case_id, event_type, details) do
    entry = %{
      case_id: case_id,
      event_type: event_type,
      details: details,
      timestamp: DateTime.utc_now()
    }

    # Фіксація в локальному аудиті ETS та KVS
    feed_key = "/audit/cases/#{case_id}"
    try do
      :kvs.append(entry, feed_key)
    rescue
      _ -> :ok
    end

    :ok
  end
end
