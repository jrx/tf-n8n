# tf-n8n

Live deployment of [`terraform-aws-n8n`](https://github.com/jrx/terraform-aws-n8n) for the `jrxhc` Terraform Cloud organization. This is **not** a reusable Terraform Registry module — it is a private root configuration that consumes one.

## What this repo does

- Runs in TFC workspace `jrxhc/n8n` (see `backend.hcl`).
- Consumes a shared VPC from the sibling TFC workspace `jrxhc/net` via `terraform_remote_state` (`networking.tf`).
- Tags every subnet of that VPC with `kubernetes.io/cluster/<cluster_name> = shared` so the AWS Load Balancer Controller auto-discovery in this cluster doesn't fight other clusters that share the VPC.
- Instantiates the `terraform-aws-n8n` module with **cost-controlled test-sizing overrides** (~$220–240/mo vs ~$440 at the module's `complete`-example defaults). See the comment block in `main.tf` — not suitable for production (single-AZ DB, no cache replication, single-pod floors on webhook and worker).
- Enables n8n's Prometheus `/metrics` endpoint and exports OTLP traces to an in-cluster Jaeger collector (`http://jaeger-otlp.monitoring.svc.cluster.local:4318`).

## Prerequisites

- Access to TFC org `jrxhc` with permissions on workspaces `n8n` (this repo) and `net` (the upstream VPC).
- A Route53 hosted zone for the parent of `n8n_domain`. The module creates the ACM certificate, the validation CNAMEs, and the alias A-record inside that zone — no manual DNS steps.
- An n8n Enterprise license key. **Do not commit it.** Pass it via `TF_VAR_n8n_license_key` or a TFC sensitive variable on the workspace.

## Apply

```bash
# 1. Configure variables (or set them in the TFC workspace UI).
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# 2. Initialize with the remote backend.
terraform init -backend-config=backend.hcl

# 3. Plan / apply.
terraform plan
terraform apply
```

Allow ~5 minutes after `apply` for the ALB to become reachable on `n8n_domain`.

## Module source

`main.tf` currently sources the module from an absolute local path:

```hcl
source = "/Users/jan/code/n8n/src/terraform-aws-n8n"
```

This works only on the maintainer's machine. **Before sharing this repo or running it from CI, switch to a pinned remote ref**, e.g.:

```hcl
source = "git::https://github.com/jrx/terraform-aws-n8n.git?ref=v0.1.0"
```

## Files

| File | Purpose |
| --- | --- |
| `main.tf` | Module call + test-sizing overrides. |
| `networking.tf` | Reads VPC from the `net` workspace and tags subnets for this cluster. |
| `variables.tf` / `outputs.tf` | Root-level inputs and pass-through outputs. |
| `providers.tf` | `aws`, `kubernetes`, `helm` provider config. The latter two authenticate against the EKS cluster the module creates. |
| `versions.tf` | `required_version` + `required_providers` + remote backend declaration. |
| `backend.hcl` | TFC backend configuration consumed via `-backend-config=`. |
| `terraform.tfvars.example` | Template for local variable values. **Never commit your filled-in `terraform.tfvars` or `*.auto.tfvars`** — they are gitignored for a reason. |
| `.terraform-docs.yml` | terraform-docs config for the README block below. |

## Secrets

The module generates two sensitive outputs you should back up immediately after the first apply:

```bash
terraform output -raw n8n_encryption_key   # losing this makes all stored n8n credentials unreadable
terraform output -raw db_password
```

Store both in a password manager. **Do not** redirect them to a file in this directory.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.12 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.12 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_n8n"></a> [n8n](#module\_n8n) | /Users/jan/code/n8n/src/terraform-aws-n8n | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ec2_tag.cluster_shared](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_tag) | resource |
| [terraform_remote_state.vpc](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region to deploy into (e.g. us-east-1, eu-west-1, ap-southeast-1). | `string` | `"us-east-1"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name for the EKS cluster. Keep to 14 characters or fewer — the module derives an ElastiCache cluster ID of `<cluster_name>-redis`, and AWS caps ElastiCache IDs at 20 chars. | `string` | `"n8n-cluster"` | no |
| <a name="input_n8n_domain"></a> [n8n\_domain](#input\_n8n\_domain) | Fully-qualified domain name for n8n (e.g. n8n.example.com). The parent zone must be hosted in Route53 (pass its ID via route53\_zone\_id). | `string` | n/a | yes |
| <a name="input_n8n_license_key"></a> [n8n\_license\_key](#input\_n8n\_license\_key) | n8n Enterprise license activation key. Get one at https://n8n.io/pricing | `string` | n/a | yes |
| <a name="input_route53_zone_id"></a> [route53\_zone\_id](#input\_route53\_zone\_id) | Route53 hosted zone ID for the parent of n8n\_domain (e.g. the zone for example.com if n8n\_domain = n8n.example.com). The module creates the ACM certificate, validation records, and alias A-record inside this zone. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional AWS tags to apply to every resource this example creates. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_hostname"></a> [alb\_hostname](#output\_alb\_hostname) | ALB hostname. The alias A-record for n8n\_domain is already created in Route53 — this output is informational. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | EKS cluster name. For EKS this is also the cluster ID (aws\_eks\_cluster.id == aws\_eks\_cluster.name). |
| <a name="output_db_password"></a> [db\_password](#output\_db\_password) | RDS PostgreSQL password — back this up in a password manager. |
| <a name="output_kubectl_config_command"></a> [kubectl\_config\_command](#output\_kubectl\_config\_command) | Command to configure kubectl for this cluster. |
| <a name="output_n8n_encryption_key"></a> [n8n\_encryption\_key](#output\_n8n\_encryption\_key) | n8n encryption key — back this up in a password manager. |
| <a name="output_n8n_url"></a> [n8n\_url](#output\_n8n\_url) | URL to access n8n once the ALB finishes provisioning (~5 min after apply). |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace n8n is deployed into. Read by tests/scripts/smoke-test.sh. |
| <a name="output_rds_endpoint"></a> [rds\_endpoint](#output\_rds\_endpoint) | RDS PostgreSQL endpoint (host address, no port). Module-managed RDS when create\_database = true in the root module, otherwise the caller-supplied db\_host. |
<!-- END_TF_DOCS -->

## Regenerating the doc block

```bash
terraform-docs markdown table --output-file README.md --output-mode inject .
```

The config in `.terraform-docs.yml` is already wired for inject mode.
