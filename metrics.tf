# ── Worker metrics Service ────────────────────────────────────────────────────
# Every n8n role serves Prometheus metrics on /metrics:5678 once N8N_METRICS
# is on (verified live on n8n 2.39.6 for main, webhook-processor and worker).
# The n8n Helm chart publishes a Service for main and webhook-processor only;
# the worker Deployment has none, and its container declares no named port,
# so a PodMonitor cannot address it either. This Service gives the worker the
# same shape as the chart's two Services (labels, `http` port name, 5678) so a
# single ServiceMonitor in the `monitoring` workspace selects all three roles.
#
# Only the ServiceMonitor consumes this; nothing routes user traffic to it.
resource "kubernetes_service_v1" "n8n_worker_metrics" {
  metadata {
    name      = "n8n-worker"
    namespace = module.n8n.namespace
    labels = {
      "app.kubernetes.io/name"       = "n8n"
      "app.kubernetes.io/instance"   = "n8n"
      "app.kubernetes.io/component"  = "worker"
      "app.kubernetes.io/managed-by" = "Terraform"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"      = "n8n"
      "app.kubernetes.io/instance"  = "n8n"
      "app.kubernetes.io/component" = "worker"
    }

    port {
      name        = "http"
      port        = 5678
      target_port = 5678
      protocol    = "TCP"
    }
  }
}
