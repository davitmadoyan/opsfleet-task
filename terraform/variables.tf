variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name. Also used as the discovery tag value for Karpenter."
  type        = string
  default     = "opsfleet-poc"
}

variable "kubernetes_version" {
  description = "Kubernetes minor version for the EKS control plane."
  type        = string
  default     = "1.33"
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version from oci://public.ecr.aws/karpenter/karpenter."
  type        = string
  default     = "1.5.0"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs_count" {
  description = "Number of availability zones to span."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
