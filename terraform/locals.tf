data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  name = var.cluster_name

  azs = slice(data.aws_availability_zones.available.names, 0, var.azs_count)

  tags = merge(
    {
      Project   = "opsfleet-task"
      ManagedBy = "Terraform"
    },
    var.tags,
  )

  karpenter_namespace = "karpenter"
  karpenter_sa_name   = "karpenter"
}
