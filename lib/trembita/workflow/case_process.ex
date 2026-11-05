defmodule Trembita.Workflow.CaseProcess do
  @moduledoc """
  BPE (Business Process Engine) оркестратор для процесу розгляду справ
  про адміністративні правопорушення у сфері безпеки дорожнього руху.
  """
  require BPE
  import BPE

  @doc """
  Завантаження BPMN визначення процесу.
  """
  def bpmn_definition do
    bpmn_path = Application.app_dir(:trembita, "priv/ecourt_process.bpmn")
    BPE.XML.load(to_charlist(bpmn_path), __MODULE__)
  end

  @doc """
  Запуск BPE-процесу для судової справи.
  """
  def start_case_workflow(case_id) do
    proc_def = bpmn_definition()
    case BPE.start(proc_def, [case_id: case_id]) do
      {:ok, bpe_pid} ->
        Trembita.ETSCache.update_case(case_id, fn current ->
          Map.put(current, :bpe_proc_id, bpe_pid)
        end)
        {:ok, bpe_pid}

      error ->
        error
    end
  end

  @doc """
  Перехід до наступного етапу процесу.
  """
  def advance(proc_id) do
    BPE.next(proc_id)
  end

  def advance(proc_id, target_flow) do
    BPE.next(proc_id, target_flow)
  end

  # --- BPE Callbacks ---

  def auth(_), do: true

  def action(_message, state) do
    result(state: state)
  end
end
