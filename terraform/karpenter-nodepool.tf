# EC2NodeClass — the AWS-level template (AMI, subnets, SG, IAM) for new nodes.
resource "kubectl_manifest" "ec2nodeclass" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiFamily = "AL2023"
      amiSelectorTerms = [
        { alias = "al2023@latest" },
      ]
      role = aws_iam_role.karpenter_node.name
      subnetSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = local.name } },
      ]
      securityGroupSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = local.name } },
      ]
      tags = {
        "karpenter.sh/discovery" = local.name
      }
    }
  })

  depends_on = [helm_release.karpenter]
}

# NodePool — the scheduling-side requirements. Karpenter picks the cheapest
# instance that satisfies every requirement, so Spot wins by default and
# falls back to On-Demand when Spot isn't available.
resource "kubectl_manifest" "nodepool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          expireAfter = "720h"
          requirements = [
            # Both architectures — developers pick via nodeSelector kubernetes.io/arch.
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64", "arm64"] },
            { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
            # Spot preferred, On-Demand fallback.
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] },
            # Compute/memory families only — skip burstable (t-family) for predictability.
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] },
            # Modern generations only.
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["2"] },
          ]
        }
      }
      limits = {
        cpu = "1000"
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  })

  depends_on = [kubectl_manifest.ec2nodeclass]
}
