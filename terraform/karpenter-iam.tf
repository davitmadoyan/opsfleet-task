# =============================================================================
# Karpenter node role
# =============================================================================
# Attached to the EC2 instances Karpenter launches. Same managed policies as
# the system managed node group, but a separate role so we can grant it
# cluster access independently.

resource "aws_iam_role" "karpenter_node" {
  name               = "${local.name}-karpenter-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each   = local.node_managed_policies
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

# Karpenter v1 references the node role by name in EC2NodeClass and creates
# the underlying instance profile itself. No aws_iam_instance_profile needed.

# Access entry so Karpenter-launched nodes can join the cluster — replaces the
# legacy aws-auth ConfigMap mapping for node IAM roles.
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}

# =============================================================================
# Karpenter controller role
# =============================================================================
# Assumed via EKS Pod Identity (no OIDC provider / IRSA needed).

data "aws_iam_policy_document" "karpenter_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${local.name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "karpenter-controller"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller.json
}

# Pod Identity association: binds the controller role to the karpenter
# ServiceAccount that the Helm chart creates.
resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = local.karpenter_namespace
  service_account = local.karpenter_sa_name
  role_arn        = aws_iam_role.karpenter_controller.arn
}

# =============================================================================
# Karpenter controller IAM policy
# =============================================================================
# Mirrors the policy AWS publishes for Karpenter v1. Actions are scoped by
# cluster tag so the controller can only manage resources belonging to *this*
# cluster, even if multiple Karpenter installations share an account.
#
# See: https://karpenter.sh/docs/reference/cloudformation/

data "aws_iam_policy_document" "karpenter_controller" {
  statement {
    sid    = "AllowScopedEC2InstanceAccessActions"
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}::image/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}::snapshot/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:security-group/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:subnet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:capacity-reservation/*",
    ]
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
  }

  statement {
    sid       = "AllowScopedEC2LaunchTemplateAccessActions"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*"]
    actions   = ["ec2:RunInstances", "ec2:CreateFleet"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedEC2InstanceActionsWithTags"
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:volume/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:spot-instances-request/*",
    ]
    actions = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.name]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedResourceCreationTagging"
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:volume/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:spot-instances-request/*",
    ]
    actions = ["ec2:CreateTags"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.name]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
  }

  statement {
    sid       = "AllowScopedResourceTagging"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*"]
    actions   = ["ec2:CreateTags"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.name]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values = [
        "eks:eks-cluster-name",
        "karpenter.sh/nodeclaim",
        "Name",
      ]
    }
  }

  statement {
    sid    = "AllowScopedDeletion"
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*",
    ]
    actions = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowRegionalReadActions"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
      "ec2:DescribeAvailabilityZones",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "AllowSSMReadActions"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${var.region}::parameter/aws/service/*"]
    actions   = ["ssm:GetParameter"]
  }

  statement {
    sid       = "AllowPricingReadActions"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["pricing:GetProducts"]
  }

  statement {
    sid       = "AllowInterruptionQueueActions"
    effect    = "Allow"
    resources = [aws_sqs_queue.karpenter.arn]
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
  }

  statement {
    sid       = "AllowPassingInstanceRole"
    effect    = "Allow"
    resources = [aws_iam_role.karpenter_node.arn]
    actions   = ["iam:PassRole"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileCreationActions"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:iam::*:instance-profile/*"]
    actions   = ["iam:CreateInstanceProfile"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [var.region]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileTagActions"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:iam::*:instance-profile/*"]
    actions   = ["iam:TagInstanceProfile"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [var.region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [var.region]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileActions"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:iam::*:instance-profile/*"]
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [var.region]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowInstanceProfileReadActions"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:iam::*:instance-profile/*"]
    actions   = ["iam:GetInstanceProfile"]
  }

  statement {
    sid       = "AllowAPIServerEndpointDiscovery"
    effect    = "Allow"
    resources = [aws_eks_cluster.this.arn]
    actions   = ["eks:DescribeCluster"]
  }
}
