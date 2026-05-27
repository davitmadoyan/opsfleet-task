# opsfleet-task

Terraform IaC for an EKS cluster autoscaled by Karpenter, supporting both x86 (`amd64`) and AWS Graviton (`arm64`) workloads on Spot (with On-Demand fallback).

See **[`terraform/README.md`](terraform/README.md)** for the deploy guide and the developer workflow for scheduling a pod on either architecture.
