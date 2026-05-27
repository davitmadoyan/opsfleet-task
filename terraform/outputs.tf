output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "region" {
  description = "AWS region of the cluster."
  value       = var.region
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "configure_kubectl" {
  description = "Command to configure kubectl for the cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.region}"
}

output "karpenter_node_role" {
  description = "IAM role name that Karpenter-launched instances assume."
  value       = aws_iam_role.karpenter_node.name
}

output "karpenter_interruption_queue" {
  description = "SQS queue name used by Karpenter for Spot interruption handling."
  value       = aws_sqs_queue.karpenter.name
}
