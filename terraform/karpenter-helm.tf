resource "helm_release" "karpenter" {
  namespace        = local.karpenter_namespace
  create_namespace = true
  name             = "karpenter"

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version

  wait = true

  values = [
    yamlencode({
      replicas = 2
      serviceAccount = {
        name = local.karpenter_sa_name
      }
      settings = {
        clusterName       = aws_eks_cluster.this.name
        clusterEndpoint   = aws_eks_cluster.this.endpoint
        interruptionQueue = aws_sqs_queue.karpenter.name
      }
      # Pin Karpenter itself to the system managed node group so it never tries
      # to schedule on a node it provisioned (which would be a chicken-and-egg
      # during disruption events).
      nodeSelector = {
        role = "system"
      }
    })
  ]

  depends_on = [
    aws_eks_node_group.system,
    aws_eks_pod_identity_association.karpenter,
    aws_eks_addon.this,
  ]
}
