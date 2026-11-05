defmodule TrembitaTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @opts Trembita.Web.Router.init([])

  setup_all do
    # Переконуємось що ETS сховище та схеми ініціалізовані
    Trembita.ETSCache.init_tables()
    :ok
  end

  test "GET /health returns healthy status" do
    conn = conn(:get, "/health") |> Trembita.Web.Router.call(@opts)
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "HEALTHY"
    assert body["bpe_engine"] == "Active"
    assert body["ets_cache"] == "Active"
  end

  test "Full end-to-end eCourt administrative case lifecycle" do
    protocol_series = "ВАБ"
    protocol_number = "#{Enum.random(100000..999999)}"

    # 1. Прийом протоколу через Трембіту з ІПНП
    payload = %{
      "protocol_series" => protocol_series,
      "protocol_number" => protocol_number,
      "violation_datetime" => "2026-11-04T10:15:00+02:00",
      "article" => "124",
      "police_department_code" => "PATROL_KYIV_01",
      "court_code" => "2604",
      "offender" => %{
        "full_name" => "Франко Іван Якович",
        "birth_date" => "1986-08-27",
        "rnokpp" => "2987654321",
        "citizenship" => "Україна",
        "address" => "м. Київ, вул. Франка, 1"
      }
    }

    conn = conn(:post, "/api/v1/trembita/ipnp/protocols", Jason.encode!(payload))
           |> put_req_header("content-type", "application/json")
           |> Trembita.Web.Router.call(@opts)

    assert conn.status == 201
    resp = Jason.decode!(conn.resp_body)
    case_id = resp["case_id"]
    assert is_binary(case_id)
    assert resp["status"] == "REGISTERED"

    # 2. Перевірка відсікання дубліката протоколу (Альтернативний потік 2)
    conn_dup = conn(:post, "/api/v1/trembita/ipnp/protocols", Jason.encode!(payload))
               |> put_req_header("content-type", "application/json")
               |> Trembita.Web.Router.call(@opts)
    assert conn_dup.status == 409
    dup_resp = Jason.decode!(conn_dup.resp_body)
    assert dup_resp["status"] == "DUPLICATE"

    # 3. Перевірка ETS кешування (ETS instead of Redis)
    {:ok, cached_case} = Trembita.ETSCache.get_case(case_id)
    assert cached_case.case_id == case_id
    assert cached_case.series == protocol_series

    # 4. Завантаження сканів канцелярією суду
    attachments_payload = %{
      "files" => [
        %{"file_name" => "scan_protocol.pdf", "document_type" => "PROTOCOL_RECEIPT", "content_base64" => "JVBERi0x..."},
        %{"file_name" => "scheme_dtp.pdf", "document_type" => "ACCIDENT_SCHEME", "content_base64" => "JVBERi0x..."}
      ]
    }
    conn_attach = conn(:post, "/api/v1/cases/#{case_id}/attachments", Jason.encode!(attachments_payload))
                  |> put_req_header("content-type", "application/json")
                  |> Trembita.Web.Router.call(@opts)
    assert conn_attach.status == 200
    assert Jason.decode!(conn_attach.resp_body)["attached_count"] == 2

    # 5. Автоматизований відбір справи за технічними критеріями (Triage)
    conn_triage = conn(:post, "/api/v1/cases/#{case_id}/triage", "")
                  |> put_req_header("content-type", "application/json")
                  |> Trembita.Web.Router.call(@opts)
    assert conn_triage.status == 200
    assert Jason.decode!(conn_triage.resp_body)["eligible"] == true

    # 6. Обробка Модулем ШІ ЄСІКС (OCR + OpenSearch + генерація проєкту рішення)
    conn_ai = conn(:post, "/api/v1/ai/process", Jason.encode!(%{"case_id" => case_id}))
              |> put_req_header("content-type", "application/json")
              |> Trembita.Web.Router.call(@opts)
    assert conn_ai.status == 202
    job_id = Jason.decode!(conn_ai.resp_body)["job_id"]

    # 7. Отримання результату ШІ
    conn_status = conn(:get, "/api/v1/ai/status/#{job_id}")
                  |> Trembita.Web.Router.call(@opts)
    assert conn_status.status == 200
    ai_res = Jason.decode!(conn_status.resp_body)
    assert ai_res["status"] == "COMPLETED"
    assert ai_res["draft_decision"]["resolution"]["fine_amount_uah"] == 850.0

    # 8. Відправка повідомлення до Дії та встановлення 5-денного строку
    conn_diia_notif = conn(:post, "/api/v1/diia/notifications", Jason.encode!(%{"case_id" => case_id, "rnokpp" => "2987654321"}))
                      |> put_req_header("content-type", "application/json")
                      |> Trembita.Web.Router.call(@opts)
    assert conn_diia_notif.status == 200
    {:ok, diia_timer} = Trembita.ETSCache.get_timer(case_id, :diia_statement)
    assert diia_timer.expired? == false

    # 9. Прийом підписаної заяви особи через «Дія.Підпис» та встановлення 15-денного процесуального строку судді
    statement_payload = %{
      "case_id" => case_id,
      "case_number" => resp["case_number"],
      "rnokpp" => "2987654321",
      "agreement_with_circumstances" => true,
      "consent_for_absence_trial" => true,
      "diia_signature_cms_base64" => "MIAGCSqGSIb3DQEHAqCAMIACAQEx..."
    }
    conn_statement = conn(:post, "/api/v1/diia/statements", Jason.encode!(statement_payload))
                     |> put_req_header("content-type", "application/json")
                     |> Trembita.Web.Router.call(@opts)
    assert conn_statement.status == 200
    {:ok, judge_timer} = Trembita.ETSCache.get_timer(case_id, :judge_review)
    assert judge_timer.expired? == false

    # 10. Перегляд справи в кабінеті судді
    conn_view = conn(:get, "/api/v1/cases/#{case_id}")
                |> Trembita.Web.Router.call(@opts)
    assert conn_view.status == 200
    case_view = Jason.decode!(conn_view.resp_body)
    assert case_view["status"] == "STATEMENT_ACCEPTED"
    assert is_map(case_view["draft_decision"])

    # 11. Ухвалення рішення суддею (SIGN_AS_IS)
    decision_payload = %{
      "action" => "SIGN_AS_IS",
      "judge_qes_cms_base64" => "MIAGCSqGSIb3DQEHAqCAMIACAQEx..."
    }
    conn_dec = conn(:post, "/api/v1/cases/#{case_id}/decision", Jason.encode!(decision_payload))
               |> put_req_header("content-type", "application/json")
               |> Trembita.Web.Router.call(@opts)
    assert conn_dec.status == 200
    assert Jason.decode!(conn_dec.resp_body)["action_recorded"] == "SIGN_AS_IS"

    # 12. Оплата штрафу через Портал Дія
    payment_payload = %{
      "case_id" => case_id,
      "transaction_id" => "TRX-77721",
      "amount_paid" => 850.0,
      "paid_at" => "2026-11-05T12:00:00Z",
      "payment_system" => "DIIA_PAY"
    }
    conn_pay = conn(:post, "/api/v1/diia/payments", Jason.encode!(payment_payload))
               |> put_req_header("content-type", "application/json")
               |> Trembita.Web.Router.call(@opts)
    assert conn_pay.status == 200

    # 13. Фінальна перевірка статусу виконання
    {:ok, final_case} = Trembita.ETSCache.get_case(case_id)
    assert final_case.status == "EXECUTED_PAID"

    # 14. Перевірка фіксації зворотного зв'язку ШІ
    feedback = Trembita.ETSCache.get_all_feedback()
    assert length(feedback) >= 1
  end

  test "Triage failure when RNOKPP is invalid (Alternative Flow 5)" do
    case_id = UUID.generate()
    case_record = %{
      case_id: case_id,
      article: "124",
      offender: %{"citizenship" => "Україна", "rnokpp" => nil},
      status: "REGISTERED"
    }
    Trembita.ETSCache.put_case(case_id, case_record)

    conn = conn(:post, "/api/v1/cases/#{case_id}/triage", "")
           |> put_req_header("content-type", "application/json")
           |> Trembita.Web.Router.call(@opts)
    assert conn.status == 422
    body = Jason.decode!(conn.resp_body)
    assert body["eligible"] == false
    assert body["reason_code"] == "MISSING_RNOKPP"
  end
end
