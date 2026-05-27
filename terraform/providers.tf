provider "aws" {
  region = var.region
}

# Kubernetes-side providers authenticate via `aws eks get-token` so the token
# is refreshed on every API call (avoids the 15-minute token expiry that
# breaks long applies when using data.aws_eks_cluster_auth).

provider "helm" {
  # helm provider v3 moved `kubernetes` from a nested block to an attribute (object).
  kubernetes = {
    host                   = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", var.region]
    }
  }
}

provider "kubectl" {
  host                   = aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", var.region]
  }
}
