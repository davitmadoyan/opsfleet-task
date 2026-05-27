module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  # /20 private subnets (4096 IPs each) so Karpenter has plenty of headroom for pods.
  private_subnets = [for k in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, k)]
  # /24 public subnets, offset so they don't overlap with private.
  public_subnets = [for k in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  enable_dns_hostnames   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  # Karpenter discovers subnets to launch nodes into via this tag.
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = local.name
  }

  tags = local.tags
}
