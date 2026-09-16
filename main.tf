locals {
  common_tags = merge(
    {
      ManagedBy = "terraform"
      Project   = "n8n"
    },
    var.tags,
  )

  # Prometheus metric families that n8n keeps off by default. The n8n
  # Monitoring Pack dashboards in the `monitoring` workspace read every one
  # of these, so they are enabled here (the producer side) and scraped there.
  # The module owns N8N_METRICS itself (n8n_metrics_enabled above); these
  # N8N_METRICS_INCLUDE_* flags are not module-managed, so they ride in
  # n8n_extra_env and apply to main, worker and webhook pods alike.
  # Env names verified against n8n 2.39.6 packages/@n8n/config/src/configs/
  # endpoints.config.ts. Flags with a default of true (execution duration
  # histogram, Node.js default metrics) are not repeated here.
  #
  # Cardinality note: the workflow_id / workflow_name labels add one series
  # per workflow per metric. Fine for a sandbox; revisit before pointing a
  # large instance at this.
  n8n_metrics_env = [
    # Connection pool gauges + acquire histogram (n8n_db_pool_*).
    { name = "N8N_METRICS_INCLUDE_DB_POOL_METRICS", value = "true" },
    # Cache hit / miss counters (n8n_cache_hits_total, n8n_cache_misses_total).
    { name = "N8N_METRICS_INCLUDE_CACHE_METRICS", value = "true" },
    # Execution data read/write counters + histograms (n8n_execution_data_*).
    { name = "N8N_METRICS_INCLUDE_EXECUTION_DATA_METRICS", value = "true" },
    # Webhook request duration histogram (n8n_webhook_request_duration_seconds).
    { name = "N8N_METRICS_INCLUDE_WEBHOOK_METRICS", value = "true" },
    # HTTP route histogram (n8n_http_request_duration_seconds) + n8n_last_activity,
    # with the status_code label the golden-signals dashboard groups by.
    { name = "N8N_METRICS_INCLUDE_API_ENDPOINTS", value = "true" },
    { name = "N8N_METRICS_INCLUDE_API_STATUS_CODE_LABEL", value = "true" },
    # Per-event counters from the message event bus
    # (n8n_workflow_started_total / _success_total / _failed_total, ...).
    { name = "N8N_METRICS_INCLUDE_MESSAGE_EVENT_BUS_METRICS", value = "true" },
    # workflow_id + workflow_name labels on the event-bus counters and
    # workflow_id on the execution duration histogram.
    { name = "N8N_METRICS_INCLUDE_WORKFLOW_ID_LABEL", value = "true" },
    { name = "N8N_METRICS_INCLUDE_WORKFLOW_NAME_LABEL", value = "true" },
    # n8n_workflow_info{workflow_id, workflow_name} gauge used to join
    # workflow_id-only series onto a readable name.
    { name = "N8N_METRICS_INCLUDE_WORKFLOW_INFO", value = "true" },
    # Instance-lifetime totals from the license metrics repository
    # (n8n_production_executions, n8n_manual_executions, n8n_workflows,
    # n8n_users, n8n_enabled_users, n8n_credentials). Refreshed every 300s
    # by default, same value on every role, so aggregate with max().
    { name = "N8N_METRICS_INCLUDE_WORKFLOW_STATISTICS", value = "true" },
    # Bull job counts as seen by each main (n8n_scaling_mode_queue_jobs_*).
    # Every main reports the same shared queue, so aggregate with max().
    { name = "N8N_METRICS_INCLUDE_QUEUE_METRICS", value = "true" },
  ]
}

# ── n8n ───────────────────────────────────────────────────────────────────────
# The module issues the ACM certificate and creates the Route53 alias record
# itself when route53_zone_id is set — single terraform apply, no manual DNS.
#
# VPC, subnets, and NAT are managed in the `net` workspace and consumed via
# data.terraform_remote_state.vpc (see networking.tf).

module "n8n" {
  source = "git::https://github.com/n8n-io/terraform-aws-n8n.git?ref=main"

  aws_region      = var.aws_region
  cluster_name    = var.cluster_name
  n8n_domain      = var.n8n_domain
  vpc_id          = data.terraform_remote_state.vpc.outputs.aws_vpc_id
  private_subnets = data.terraform_remote_state.vpc.outputs.aws_private_subnets
  public_subnets  = data.terraform_remote_state.vpc.outputs.aws_public_subnets
  vpc_cidr_block  = data.terraform_remote_state.vpc.outputs.aws_cidr
  route53_zone_id = var.route53_zone_id

  n8n_license_key = var.n8n_license_key

  # ── Test sizing overrides ────────────────────────────────────────────────────
  # Minimal configuration for cost-controlled testing (~$220-240/mo vs ~$440
  # at root-module defaults). All values use existing module inputs — no
  # changes to the n8n-io/n8n/aws module are required.
  # Not suitable for production: single-AZ DB, no cache replication, single-pod
  # webhook and worker floors. Remove this block to use the module defaults.

  # ── Compute: 2× t3.medium ≈ $60/mo, vs 3× t3.xlarge ≈ $150 ─────────────────
  node_instance_type = "t3.medium" # 2 vCPU / 4 GB
  node_desired       = 2
  node_min           = 2
  node_max           = 4 # leave room for HPA scale-out tests

  # ── Database: cheapest single-AZ RDS ────────────────────────────────────────
  db_instance_class    = "db.t3.micro" # 2 vCPU / 1 GB, ~$13/mo
  db_allocated_storage = 20            # validation floor
  db_multi_az          = false         # no standby

  # ── Redis: cheapest ElastiCache ─────────────────────────────────────────────
  redis_node_type = "cache.t3.micro" # ~$12/mo

  # ── Replica floors: drop to 1 each so the cluster is sized for idle ────────
  # Keep maxes at defaults — autoscaler can still grow under load.
  # Keep main at 2 to preserve Enterprise multi-main mode. The current module
  # supports a floor of 1, but that disables multi-main and clamps its HPA to 1.
  # That topology change is not part of this upgrade.
  n8n_main_hpa_min_replicas    = 2
  n8n_webhook_hpa_min_replicas = 1
  n8n_worker_keda_min_replicas = 1

  # ── Pod resource requests: shrink to fit t3.medium (~1.7 vCPU usable) ──────
  # At min replicas, including runner sidecars: 1100m CPU / 2304Mi RAM,
  # leaving headroom for addons (lbc, keda, metrics-server, cluster-autoscaler).
  n8n_main_cpu_request    = "250m"
  n8n_main_cpu_limit      = "1000m"
  n8n_main_memory_request = "512Mi"
  n8n_main_memory_limit   = "1Gi"

  n8n_worker_cpu_request    = "200m"
  n8n_worker_cpu_limit      = "500m"
  n8n_worker_memory_request = "256Mi"
  n8n_worker_memory_limit   = "512Mi"

  n8n_webhook_cpu_request    = "100m"
  n8n_webhook_cpu_limit      = "300m"
  n8n_webhook_memory_request = "256Mi"
  n8n_webhook_memory_limit   = "512Mi"

  n8n_task_runner_cpu_request    = "100m"
  n8n_task_runner_cpu_limit      = "500m"
  n8n_task_runner_memory_request = "256Mi"
  n8n_task_runner_memory_limit   = "512Mi"

  # ── Execution tuning: match the tiny DB and worker count ───────────────────
  n8n_worker_concurrency          = 5
  n8n_execution_concurrency_limit = 20
  db_postgresdb_pool_size         = 5
  n8n_pruning_max_count           = 1000
  n8n_pruning_max_age             = 72 # 3 days

  # Bump Helm timeout slightly — small nodes cold-start slower.
  n8n_helm_timeout = 900

  # ── Observability ─────────────────────────────────────────────────────────
  # Exposes n8n's Prometheus metrics on /metrics (port 5678). The module only
  # sets N8N_METRICS=true; scrape config (annotations / ServiceMonitor) is left
  # to whatever monitoring stack runs in the cluster.
  n8n_metrics_enabled = true

  # OTEL tracing: exports workflow/node spans to the in-cluster Jaeger OTLP
  # receiver in the monitoring namespace. Applies to all n8n containers
  # (main, worker, webhook processor).
  n8n_otel_enabled                   = true
  n8n_otel_traces_include_node_spans = true
  n8n_otel_exporter_otlp_endpoint    = "http://jaeger-otlp.monitoring.svc.cluster.local:4318"

  # ── UI noise reduction (test env) ───────────────────────────────────────
  # Skip the personalization survey on first login and hide the templates
  # gallery — neither is useful in a short-lived test environment.
  n8n_personalization_enabled = false
  n8n_templates_enabled       = false

  # ── Log streaming → Grafana Alloy (Enterprise feature) ─────────────────
  # Requires n8n >= 2.19.0 and a license that includes log streaming.
  # The module's chart default supplies the application image. Managed-by-env locks
  # the Log Streaming UI read-only; destinations reapply on every pod start.
  # The Alloy syslog receiver (monitoring namespace, 1514/tcp) is managed
  # outside this repo — if it's down, events are dropped silently.
  # NOTE: key casing below is the verbatim n8n JSON contract — app_name is
  # snake_case while subscribedEvents / anonymizeAuditMessages are camelCase.
  # The module jsonencode()s this list as-is; do not "normalize" the keys.
  n8n_log_streaming_managed_by_env = true
  n8n_log_streaming_destinations = [
    {
      type                   = "syslog"
      label                  = "Alloy syslog"
      enabled                = true
      host                   = "alloy-syslog.monitoring.svc.cluster.local"
      port                   = 1514
      protocol               = "tcp"
      app_name               = "n8n"
      subscribedEvents       = ["n8n.audit", "n8n.node", "n8n.queue"]
      anonymizeAuditMessages = true
    },
  ]

  n8n_extra_env = concat(var.n8n_extra_env, local.n8n_metrics_env)

  tags = local.common_tags
}
