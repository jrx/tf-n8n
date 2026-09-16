# ── App DNS + access ──────────────────────────────────────────────────────────

output "alb_hostname" {
  description = "ALB hostname. The alias A-record for n8n_domain is already created in Route53 — this output is informational."
  value       = module.n8n.alb_hostname
}

output "n8n_url" {
  description = "URL to access n8n once the ALB finishes provisioning (~5 min after apply)."
  value       = module.n8n.n8n_url
}

output "kubectl_config_command" {
  description = "Command to configure kubectl for this cluster."
  value       = module.n8n.kubectl_config_command
}

output "cluster_name" {
  description = "EKS cluster name. For EKS this is also the cluster ID (aws_eks_cluster.id == aws_eks_cluster.name)."
  value       = module.n8n.cluster_name
}

output "namespace" {
  description = "Kubernetes namespace n8n is deployed into. Read by tests/scripts/smoke-test.sh."
  value       = module.n8n.namespace
}

# ── Infrastructure ────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host address, no port). Module-managed RDS when create_database = true in the root module, otherwise the caller-supplied db_host."
  value       = module.n8n.rds_endpoint
}

# Read by the `monitoring` workspace to point its Redis exporter at the Bull
# queue (n8n Monitoring Pack "Queue & Workers" dashboard). Plaintext, no
# AUTH: redis_transit_encryption_enabled is left at the module default here.
# If that ever changes, the exporter in tf-monitoring needs TLS + the token.
output "redis_endpoint" {
  description = "ElastiCache Redis host n8n's Bull queue lives on (host only, no port)."
  value       = module.n8n.redis_endpoint
}

output "redis_port" {
  description = "Port for redis_endpoint."
  value       = module.n8n.redis_port
}

# ── Secrets ───────────────────────────────────────────────────────────────────
# Retrieve with: terraform output -raw <name>

output "n8n_encryption_key" {
  description = "n8n encryption key — back this up in a password manager."
  value       = module.n8n.n8n_encryption_key
  sensitive   = true
}

output "db_password" {
  description = "RDS PostgreSQL password — back this up in a password manager."
  value       = module.n8n.db_password
  sensitive   = true
}
