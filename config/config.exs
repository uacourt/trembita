import Config

config :kvs,
  schema: [:kvs, BPE.Metainfo],
  dba: :kvs_mnesia,
  dba_st: :kvs_stream

config :bpe,
  driver: :exclusive,
  procmodules: [Trembita.Workflow.CaseProcess, BPE]

config :trembita,
  port: 4000,
  opensearch_url: System.get_env("OPENSEARCH_URL", "http://localhost:9200")

