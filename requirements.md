openapi: 3.1.0
info:
  title: ЄСІКС AI eCourt & Trembita Integration API
  version: 1.0.0
  description: >
    Технічні Вимоги до інтерфейсів електронної взаємодії Єдиної судової
    інформаційно-комунікаційної системи (ЄСІКС) в межах експериментального проєкту
    опрацювання матеріалів про адміністративні правопорушення у сфері безпеки дорожнього
    руху (ст. 122(4), 124, 126 ч. 3, 5, ст. 130 КУпАП) з використанням технологій
    штучного інтелекту, системи «Трембіта», Д-3, Порталу Дія та ЄДРСР.
servers:
  - url: https://api.court.gov.ua/api/v1
    description: Виробничий шлюз ЄСІКС (Трембіта / API Gateway)
  - url: http://localhost:4000/api/v1
    description: Локальне середовище розробки / прототип

paths:
  /trembita/ipnp/protocols:
    post:
      summary: Прийом протоколу про адміністративне правопорушення з ІПНП Нацполіції
      description: >
        Шлюзовий ендпойнт для прийому структурованих відомостей протоколу через
        систему електронної взаємодії «Трембіта» (SEVDEIR/X-Road). Здійснює формато-логічний
        контроль, перевірку на дублювання за серією/номером, збагачення РНОКПП (за наявності)
        та ініціацію створення облікової картки справи в Д-3.
      operationId: receivePoliceProtocol
      tags:
        - Trembita / IPNP Inbound
      parameters:
        - $ref: '#/components/parameters/X-Road-Client'
        - $ref: '#/components/parameters/X-Road-Service'
        - $ref: '#/components/parameters/X-Road-UserId'
        - $ref: '#/components/parameters/X-Road-Id'
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/PoliceProtocolPayload'
      responses:
        '201':
          description: Протокол успішно зареєстровано, створено облікову картку в Д-3
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/CaseRegistrationResponse'
        '400':
          description: Відомості не відповідають узгодженому формату (Альтернативний потік 1)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'
        '409':
          description: Протокол з такою серією та номером уже надходив (Альтернативний потік 2)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/DuplicateProtocolResponse'
        '502':
          description: Помилка електронної взаємодії між системами (Альтернативний потік 10)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'

  /cases/{case_id}/attachments:
    post:
      summary: Завантаження сканованих паперових матеріалів канцелярією суду
      description: >
        Реєстрація та долучення електронних скан-копій паперових матеріалів справи
        (протокол-чек, схема ДТП, пояснення) працівником канцелярії суду до облікової
        картки справи в Д-3.
      operationId: uploadCaseAttachments
      tags:
        - Court Clerk & Docketing (D-3)
      parameters:
        - name: case_id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/AttachmentUploadRequest'
      responses:
        '200':
          description: Матеріали успішно долучено до справи
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/AttachmentUploadResponse'
        '404':
          description: Справу не знайдено в обліковій системі Д-3
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'
        '422':
          description: Неможливо зіставити матеріали з відомостями протоколу (Альтернативний потік 3)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'

  /cases/{case_id}/triage:
    post:
      summary: Автоматизований відбір справи за технічними критеріями
      description: >
        Перевірка відповідності справи технічним критеріям експериментального проєкту:
        статті КУпАП (122-4, 124, 126 ч.3/5, 130), наявність верифікованого РНОКПП,
        громадянство України, вік >= 18 років, суд є активним учасником проєкту.
      operationId: triageCase
      tags:
        - ESICS Core Engine
      parameters:
        - name: case_id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: Справа відповідає критеріям та передається в пайплайн ШІ
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/TriageSuccessResponse'
        '422':
          description: Справа не відповідає критеріям, передача до загального порядку (Альтернативний потік 5)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/TriageRejectionResponse'

  /ai/process:
    post:
      summary: Ініціація опрацювання матеріалів справи Модулем ШІ ЄСІКС
      description: >
        Асинхронний запуск комплексу ШІ: оптичне розпізнавання тексту (OCR), формато-логічний
        контроль реквізитів, пошук прецедентної практики в ЄДРСР через OpenSearch та
        генерація структурованого проєкту судового рішення (ст. 283 КУпАП).
      operationId: triggerAIProcessing
      tags:
        - ESICS AI Module
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/AIProcessRequest'
      responses:
        '202':
          description: Запит прийнято до черги опрацювання ШІ
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/AIJobCreatedResponse'
        '503':
          description: Модуль ШІ недоступний або таймаут (Альтернативний потік 6)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'

  /ai/status/{job_id}:
    get:
      summary: Отримання статусу та результату опрацювання Модулем ШІ
      description: Перевірка статусу виконання OCR та генерації проєкту рішення
      operationId: getAIJobStatus
      tags:
        - ESICS AI Module
      parameters:
        - name: job_id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: Проєкт рішення сформовано та валідовано
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/AIJobStatusResponse'
        '422':
          description: Низька розпізнаваність або помилка генерації (Альтернативні потоки 7, 8)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/AIFailureResponse'

  /diia/notifications:
    post:
      summary: Відправка повідомлення правопорушнику в застосунок Дія
      description: >
        Передача до Порталу Дія відомостей про опрацювання справи ШІ та встановлення
        5-денного строку для подання заяви про згоду з обставинами правопорушення.
      operationId: sendDiiaNotification
      tags:
        - Diia Portal Integration
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/DiiaNotificationRequest'
      responses:
        '200':
          description: Повідомлення успішно доставлено в застосунок Дія
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/DiiaNotificationResponse'
        '404':
          description: Отримувача не знайдено в Дії або не автентифіковано (Альтернативний потік 11)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'

  /diia/statements:
    post:
      summary: Прийом підписаної заяви особи з Порталу Дія
      description: >
        Отримання сформованої та підписаної «Дія.Підписом» заяви правопорушника про згоду
        з обставинами протоколу та розгляд без його участі. Перевірка КЕП та запуск
        15-денного процесуального таймера для судді.
      operationId: submitDiiaStatement
      tags:
        - Diia Portal Integration
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/SignedStatementPayload'
      responses:
        '200':
          description: Заяву верифіковано та долучено до справи в Д-3, статус «Заяву отримано»
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/StatementAcceptedResponse'
        '422':
          description: Помилка валідації КЕП або невідповідність справи (Альтернативний потік 17)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'

  /diia/refusals:
    post:
      summary: Фіксація відмови або неподання заяви особою у Дії
      description: >
        Обробка події натискання «Не подавати заяву» (Альтернативний потік 12) або
        спливу 5-денного строку (Альтернативний потік 13). Переведення справи на загальний розгляд.
      operationId: handleDiiaRefusal
      tags:
        - Diia Portal Integration
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/StatementRefusalRequest'
      responses:
        '200':
          description: Відмову зафіксовано в журналі подій та картці Д-3
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/StandardAckResponse'

  /cases/{case_id}:
    get:
      summary: Отримання повної облікової картки справи для кабінету судді
      description: >
        Надання судді/помічнику комплексу матеріалів: протокол, скан-копії, згенерований
        ШІ проєкт постанови, релевантні прецеденти ЄДРСР, підписана заява особи з Дії.
      operationId: getJudgeCaseDetails
      tags:
        - Judicial Workbench
      parameters:
        - name: case_id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: Дані справи для судового розгляду
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/JudgeCaseView'

  /cases/{case_id}/decision:
    post:
      summary: Ухвалення судового рішення суддею (Підписати / Редагувати / Відхилити)
      description: >
        Фіксація процесуальної дії судді: підписання КЕП без змін, коригування
        мотивувальної частини/санкції в межах КУпАП з підписанням КЕП, або відхилення
        з мотивацією та поверненням до загального порядку (Альтернативний потік 19).
      operationId: judgeResolveCase
      tags:
        - Judicial Workbench
      parameters:
        - name: case_id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/JudgeDecisionActionRequest'
      responses:
        '200':
          description: Рішення підписано або відхилено, запущено ланцюг публікації та сповіщень
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/JudgeDecisionActionResponse'
        '409':
          description: Прострочено 15-денний регламентний термін (попередження) або конфлікт версій
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'

  /trembita/ipnp/decisions:
    post:
      summary: Передача підписаного судового рішення до ІПНП через Трембіту
      description: >
        Експорт постанови суду з КЕП судді та структурованими даними (штраф, позбавлення права)
        до Інформаційного порталу Нацполіції для внесення в реєстри та виконання.
      operationId: transmitDecisionToPolice
      tags:
        - Trembita / IPNP Outbound
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/DecisionToPolicePayload'
      responses:
        '200':
          description: Постанову прийнято ІПНП
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/StandardAckResponse'

  /edrsr/publish:
    post:
      summary: Внесення судового рішення до Єдиного державного реєстру судових рішень
      description: Відправка тексту постанови, КЕП судді та метаданих до ЄДРСР
      operationId: publishToEDRSR
      tags:
        - Registries (EDRSR)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/EDRSRPublishRequest'
      responses:
        '200':
          description: Рішення зареєстровано в ЄДРСР
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/EDRSRPublishResponse'

  /diia/decisions:
    post:
      summary: Передача відомостей про судове рішення та платіжних реквізитів у Дію
      description: >
        Надсилання тексту постанови, резолютивної частини та платіжних реквізитів
        для сплати штрафу правопорушником у мобільному застосунку Дія.
      operationId: pushDecisionToDiia
      tags:
        - Diia Portal Integration
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/DiiaDecisionNoticeRequest'
      responses:
        '200':
          description: Постанову відображено в кабінеті Дії
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/StandardAckResponse'

  /diia/payments:
    post:
      summary: Отримання підтвердження сплати штрафу з платіжного сервісу Дії
      description: >
        Callback-повідомлення про здійснення оплати штрафу через інтегрований
        платіжний сервіс Дії та фіксація виконання постанови в Д-3.
      operationId: receiveFinePaymentConfirmation
      tags:
        - Payment & Execution
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/PaymentConfirmationPayload'
      responses:
        '200':
          description: Відомості про сплату штрафу внесено до облікової картки
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/StandardAckResponse'
        '400':
          description: Помилка або недійсний чек платіжної транзакції (Альтернативний потік 22)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'

  /ai/feedback:
    post:
      summary: Збереження знеособленого запису для моніторингу та оцінки якості ШІ
      description: >
        Фіксація початкового проєкту ШІ, підсумкової редакції судді, дій судді та версії
        моделі ШІ без персональних даних для безперервного покращення якості моделей.
      operationId: storeAIEvaluationFeedback
      tags:
        - AI Quality & Evaluation
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/AIEvaluationFeedbackPayload'
      responses:
        '201':
          description: Знеособлений метричний запис збережено
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/StandardAckResponse'

components:
  parameters:
    X-Road-Client:
      name: X-Road-Client
      in: header
      required: true
      schema:
        type: string
        example: SEVDEIR/GOV/34614292/90_ElectronicCourt_prod
    X-Road-Service:
      name: X-Road-Service
      in: header
      required: true
      schema:
        type: string
        example: SEVDEIR/GOV/26255795/16_EDRSR_prod
    X-Road-UserId:
      name: X-Road-UserId
      in: header
      required: true
      schema:
        type: string
        example: UA12345678
    X-Road-Id:
      name: X-Road-Id
      in: header
      required: true
      schema:
        type: string
        example: 4a2b9f3d-51a1-4322-92fe-b58f844b2f1e

  schemas:
    PoliceProtocolPayload:
      type: object
      required:
        - protocol_series
        - protocol_number
        - violation_datetime
        - article
        - part
        - police_department_code
        - court_code
        - offender
      properties:
        protocol_series:
          type: string
          example: 'ААБ'
        protocol_number:
          type: string
          example: '123456'
        violation_datetime:
          type: string
          format: date-time
          example: '2026-11-04T10:15:00+02:00'
        article:
          type: string
          enum: ['122-4', '124', '126', '130']
          example: '124'
        part:
          type: integer
          nullable: true
          example: null
        police_department_code:
          type: string
          example: 'PATROL_KYIV_01'
        court_code:
          type: string
          example: '2604'
        offender:
          $ref: '#/components/schemas/OffenderInfo'
        vehicle:
          type: object
          properties:
            brand:
              type: string
              example: 'Toyota Camry'
            plate_number:
              type: string
              example: 'AA1234BB'

    OffenderInfo:
      type: object
      required:
        - full_name
        - birth_date
        - citizenship
      properties:
        full_name:
          type: string
          example: 'Шевченко Петро Олексійович'
        birth_date:
          type: string
          format: date
          example: '1995-05-12'
        rnokpp:
          type: string
          pattern: '^[0-9]{10}$'
          nullable: true
          example: '3123456789'
        citizenship:
          type: string
          example: 'Україна'
        address:
          type: string
          example: 'м. Київ, вул. Хрещатик, 10, кв. 5'

    CaseRegistrationResponse:
      type: object
      properties:
        case_id:
          type: string
          format: uuid
        case_number:
          type: string
          example: '757/12345/26-п'
        d3_docket_id:
          type: string
          example: 'D3-2026-98124'
        status:
          type: string
          example: 'REGISTERED'
        created_at:
          type: string
          format: date-time

    DuplicateProtocolResponse:
      type: object
      properties:
        status:
          type: string
          example: 'DUPLICATE'
        existing_case_id:
          type: string
          format: uuid
        message:
          type: string
          example: 'Відомості з протоколу серії ААБ № 123456 вже надійшли раніше'

    AttachmentUploadRequest:
      type: object
      required:
        - files
      properties:
        files:
          type: array
          items:
            type: object
            required:
              - file_name
              - document_type
              - content_base64
            properties:
              file_name:
                type: string
                example: 'scan_protocol_receipt.pdf'
              document_type:
                type: string
                enum: ['PROTOCOL_RECEIPT', 'ACCIDENT_SCHEME', 'EXPLANATION', 'TEST_REPORT']
              content_base64:
                type: string

    AttachmentUploadResponse:
      type: object
      properties:
        case_id:
          type: string
          format: uuid
        attached_count:
          type: integer
          example: 2
        status:
          type: string
          example: 'ATTACHED'

    TriageSuccessResponse:
      type: object
      properties:
        eligible:
          type: boolean
          example: true
        criteria_checks:
          type: object
          properties:
            target_article_valid:
              type: boolean
              example: true
            rnokpp_present:
              type: boolean
              example: true
            citizenship_ua:
              type: boolean
              example: true
            adult_at_offense:
              type: boolean
              example: true
            court_pilot_active:
              type: boolean
              example: true
        next_action:
          type: string
          example: 'AI_PROCESSING_TRIGGERED'

    TriageRejectionResponse:
      type: object
      properties:
        eligible:
          type: boolean
          example: false
        reason_code:
          type: string
          example: 'MISSING_RNOKPP'
        description:
          type: string
          example: 'У матеріалах відсутній верифікований РНОКПП особи'
        fallback_action:
          type: string
          example: 'GENERAL_LEGAL_PROCEDURE'

    AIProcessRequest:
      type: object
      required:
        - case_id
      properties:
        case_id:
          type: string
          format: uuid
        priority:
          type: string
          enum: ['NORMAL', 'HIGH']
          default: 'NORMAL'

    AIJobCreatedResponse:
      type: object
      properties:
        job_id:
          type: string
          format: uuid
        case_id:
          type: string
          format: uuid
        status:
          type: string
          example: 'QUEUED'

    AIJobStatusResponse:
      type: object
      properties:
        job_id:
          type: string
          format: uuid
        status:
          type: string
          enum: ['PENDING', 'PROCESSING', 'COMPLETED', 'FAILED']
        ocr_confidence_score:
          type: number
          format: float
          example: 0.94
        ai_model_version:
          type: string
          example: 'ESICS-AI-KUPAP-v2.4'
        draft_decision:
          $ref: '#/components/schemas/DraftDecision'
        jurisprudence_references:
          type: array
          items:
            $ref: '#/components/schemas/JurisprudenceReference'

    AIFailureResponse:
      type: object
      properties:
        job_id:
          type: string
          format: uuid
        error_code:
          type: string
          enum: ['OCR_CONFIDENCE_LOW', 'INCONSISTENT_FACTS', 'GENERATION_ERROR']
        reason:
          type: string
          example: 'Рівень технічної розпізнаваності (0.61) нижче встановленого порогу (0.85)'
        documents_failed:
          type: array
          items:
            type: string
            example: 'ACCIDENT_SCHEME'

    DraftDecision:
      type: object
      required:
        - court_name
        - judge_name
        - intro
        - circumstances
        - resolution
      properties:
        court_name:
          type: string
          example: 'Печерський районний суд міста Києва'
        judge_name:
          type: string
          example: 'Іванов І. І.'
        intro:
          type: string
        circumstances:
          type: string
        resolution:
          type: object
          properties:
            sanction_type:
              type: string
              enum: ['FINE', 'LICENSE_REVOCATION', 'ADMIN_ARREST', 'DISMISSAL']
            fine_amount_uah:
              type: number
              example: 850.00
            court_fee_uah:
              type: number
              example: 605.60
            revocation_months:
              type: integer
              nullable: true
              example: null
            dismissal_ground:
              type: string
              nullable: true

    JurisprudenceReference:
      type: object
      properties:
        edrsr_cause_number:
          type: string
          example: '757/4512/25-п'
        judgment_date:
          type: string
          format: date
          example: '2025-08-14'
        similarity_score:
          type: number
          example: 0.89
        relevance_summary:
          type: string
          example: 'Аналогічні обставини ДТП на перехресті при неподанні сигналу повороту'

    DiiaNotificationRequest:
      type: object
      required:
        - case_id
        - rnokpp
        - deadline_days
      properties:
        case_id:
          type: string
          format: uuid
        rnokpp:
          type: string
          example: '3123456789'
        deadline_days:
          type: integer
          default: 5
        message_title:
          type: string
          example: 'Судова справа про адміністративне правопорушення'

    DiiaNotificationResponse:
      type: object
      properties:
        delivery_id:
          type: string
          format: uuid
        delivered_at:
          type: string
          format: date-time
        deadline_at:
          type: string
          format: date-time

    SignedStatementPayload:
      type: object
      required:
        - case_id
        - case_number
        - rnokpp
        - agreement_with_circumstances
        - consent_for_absence_trial
        - diia_signature_cms_base64
      properties:
        case_id:
          type: string
          format: uuid
        case_number:
          type: string
          example: '757/12345/26-п'
        rnokpp:
          type: string
          example: '3123456789'
        agreement_with_circumstances:
          type: boolean
          example: true
        consent_for_absence_trial:
          type: boolean
          example: true
        diia_signature_cms_base64:
          type: string
          description: Кваліфікований електронний підпис «Дія.Підпис» у форматі CMS/CAdES

    StatementAcceptedResponse:
      type: object
      properties:
        status:
          type: string
          example: 'STATEMENT_ACCEPTED'
        judge_notification_sent:
          type: boolean
          example: true
        judicial_timer_days:
          type: integer
          example: 15

    StatementRefusalRequest:
      type: object
      required:
        - case_id
        - reason
      properties:
        case_id:
          type: string
          format: uuid
        reason:
          type: string
          enum: ['USER_DECLINED', 'TIMEOUT_EXPIRED']

    JudgeCaseView:
      type: object
      properties:
        case_id:
          type: string
          format: uuid
        case_number:
          type: string
        status:
          type: string
        protocol:
          $ref: '#/components/schemas/PoliceProtocolPayload'
        statement:
          $ref: '#/components/schemas/SignedStatementPayload'
        draft_decision:
          $ref: '#/components/schemas/DraftDecision'
        relevant_practice:
          type: array
          items:
            $ref: '#/components/schemas/JurisprudenceReference'

    JudgeDecisionActionRequest:
      type: object
      required:
        - action
      properties:
        action:
          type: string
          enum: ['SIGN_AS_IS', 'EDIT_AND_SIGN', 'REJECT']
        edited_text:
          type: string
          nullable: true
        rejection_reason:
          type: string
          nullable: true
        judge_qes_cms_base64:
          type: string
          description: КЕП судді

    JudgeDecisionActionResponse:
      type: object
      properties:
        decision_id:
          type: string
          format: uuid
        case_id:
          type: string
          format: uuid
        action_recorded:
          type: string
        edrsr_dispatch_status:
          type: string
          example: 'PENDING'
        police_dispatch_status:
          type: string
          example: 'PENDING'
        diia_dispatch_status:
          type: string
          example: 'PENDING'

    DecisionToPolicePayload:
      type: object
      required:
        - case_number
        - protocol_series
        - protocol_number
        - decision_date
        - sanction
        - signed_pdf_base64
      properties:
        case_number:
          type: string
        protocol_series:
          type: string
        protocol_number:
          type: string
        decision_date:
          type: string
          format: date
        sanction:
          type: object
          properties:
            fine_amount_uah:
              type: number
            license_revocation_months:
              type: integer
              nullable: true
        signed_pdf_base64:
          type: string

    EDRSRPublishRequest:
      type: object
      required:
        - case_number
        - court_code
        - decision_date
        - full_text_xml
        - signature_base64
      properties:
        case_number:
          type: string
        court_code:
          type: string
        decision_date:
          type: string
          format: date
        full_text_xml:
          type: string
        signature_base64:
          type: string

    EDRSRPublishResponse:
      type: object
      properties:
        edrsr_id:
          type: string
          example: 'EDRSR-2026-1049281'
        registration_number:
          type: string
        registered_at:
          type: string
          format: date-time

    DiiaDecisionNoticeRequest:
      type: object
      required:
        - case_id
        - rnokpp
        - fine_amount
        - payment_iban
      properties:
        case_id:
          type: string
          format: uuid
        rnokpp:
          type: string
        fine_amount:
          type: number
        court_fee:
          type: number
        payment_iban:
          type: string
        payment_purpose:
          type: string

    PaymentConfirmationPayload:
      type: object
      required:
        - case_id
        - transaction_id
        - amount_paid
        - paid_at
        - payment_system
      properties:
        case_id:
          type: string
          format: uuid
        transaction_id:
          type: string
          example: 'TRX-94810284'
        amount_paid:
          type: number
          example: 850.00
        paid_at:
          type: string
          format: date-time
        payment_system:
          type: string
          example: 'DIIA_PAY_PORTMONE'

    AIEvaluationFeedbackPayload:
      type: object
      required:
        - ai_model_version
        - judge_action
        - original_draft_hash
        - final_decision_hash
      properties:
        case_id_anonymized:
          type: string
          example: 'anon_f4e19b'
        article:
          type: string
          example: '124'
        ai_model_version:
          type: string
          example: 'ESICS-AI-KUPAP-v2.4'
        judge_action:
          type: string
          enum: ['SIGN_AS_IS', 'EDIT_AND_SIGN', 'REJECT']
        edit_distance_ratio:
          type: number
          example: 0.04
        original_draft_hash:
          type: string
        final_decision_hash:
          type: string

    StandardAckResponse:
      type: object
      properties:
        status:
          type: string
          example: 'OK'
        timestamp:
          type: string
          format: date-time

    ErrorResponse:
      type: object
      required:
        - error_code
        - message
      properties:
        error_code:
          type: string
          example: 'VALIDATION_FAILED'
        message:
          type: string
          example: 'Відомості не відповідають узгодженому формату обміну'
        details:
          type: array
          items:
            type: string
