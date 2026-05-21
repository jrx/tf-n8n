data "terraform_remote_state" "vpc" {
  backend = "remote"
  config = {
    workspaces = {
      name = "net"
    }
    hostname     = "app.terraform.io"
    organization = "jrxhc"
  }
}

# ── Cluster discovery tags on shared subnets ──────────────────────────────────
# The shared VPC's subnets are managed in the `net` workspace and tagged for
# other clusters (e.g. jrx-dev). The AWS Load Balancer Controller's subnet
# auto-discovery filters out subnets carrying a kubernetes.io/cluster/<name>
# tag for a different cluster, so we explicitly add a `shared` tag for this
# cluster on every subnet we consume. Using aws_ec2_tag (vs subnet resources)
# keeps ownership scoped to this workspace and leaves other clusters' tags
# untouched on destroy.

locals {
  all_subnets = concat(
    data.terraform_remote_state.vpc.outputs.aws_public_subnets,
    data.terraform_remote_state.vpc.outputs.aws_private_subnets,
  )
}

resource "aws_ec2_tag" "cluster_shared" {
  for_each    = toset(local.all_subnets)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}
