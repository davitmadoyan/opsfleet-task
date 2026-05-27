locals {
  # eks-pod-identity-agent is required for Karpenter's controller pod to receive
  # credentials via the aws_eks_pod_identity_association resource below.
  cluster_addons = toset([
    "vpc-cni",
    "coredns",
    "kube-proxy",
    "eks-pod-identity-agent",
  ])
}

data "aws_eks_addon_version" "this" {
  for_each           = local.cluster_addons
  addon_name         = each.value
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "this" {
  for_each = local.cluster_addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  addon_version               = data.aws_eks_addon_version.this[each.value].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags

  depends_on = [aws_eks_node_group.system]
}
