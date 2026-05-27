# EKS + Karpenter Terraform POC

Terraform IaC that provisions an EKS cluster autoscaled by Karpenter, capable of running workloads on **both x86 (`amd64`) and AWS Graviton (`arm64`)** instances, with **Spot preferred and On-Demand fallback**.

## What this deploys

- **VPC** — `/16` across 3 AZs, public + private subnets, single NAT gateway (POC cost trade-off; see [Production hardening](#production-hardening))
- **EKS cluster** — Kubernetes `1.33` by default, modern access-entry auth (no aws-auth ConfigMap)
- **System managed node group** — 2× `t3.medium` On-Demand to run CoreDNS, kube-proxy, and the Karpenter controller itself
- **EKS addons** — `vpc-cni`, `coredns`, `kube-proxy`, `eks-pod-identity-agent`
- **Karpenter v1.5** — installed via Helm; controller authenticates via EKS Pod Identity (no OIDC provider)
- **Karpenter `NodePool` + `EC2NodeClass`** — multi-arch (`amd64` + `arm64`), capacity-type `[spot, on-demand]`, instance categories `c/m/r`, generation `> 2`, consolidation enabled
- **Spot interruption handling** — SQS queue + EventBridge rules for Spot Interruption, Rebalance Recommendation, EC2 state change, and AWS Health events

## Repository layout

```
terraform/
├── versions.tf                # Terraform + provider versions
├── providers.tf               # aws / kubernetes / helm / kubectl provider config
├── variables.tf               # tunable inputs
├── locals.tf                  # shared values + data sources
├── outputs.tf
├── vpc.tf                     # community VPC module
├── eks-cluster.tf             # cluster + IAM + creator-admin access entry
├── eks-node-group.tf          # bootstrap managed node group
├── eks-addons.tf              # vpc-cni / coredns / kube-proxy / pod-identity-agent
├── karpenter-iam.tf           # controller + node IAM, scoped to this cluster
├── karpenter-interruption.tf  # SQS + EventBridge for Spot interruption
├── karpenter-helm.tf          # Helm release
├── karpenter-nodepool.tf      # EC2NodeClass + NodePool manifests
└── examples/
    ├── x86-deployment.yaml    # nodeSelector kubernetes.io/arch: amd64
    └── arm64-deployment.yaml  # nodeSelector kubernetes.io/arch: arm64
```

## Prerequisites

- **Terraform** ≥ 1.6
- **AWS CLI v2** configured with credentials that can create VPC / EKS / IAM / SQS / EventBridge resources (admin-equivalent for the POC)
- **kubectl** ≥ 1.30

> The IAM principal that runs `terraform apply` is granted cluster-admin via `bootstrap_cluster_creator_admin_permissions = true`. The Kubernetes, Helm, and kubectl providers in this same apply use `aws eks get-token` to talk to the API as that same principal — so the apply is self-contained.

## Deploy

```sh
cd terraform
terraform init
terraform apply
```

Provisioning takes ~12–15 minutes (VPC ≈ 2 min, EKS control plane ≈ 9 min, node group + addons + Karpenter ≈ 3 min).

After apply, configure kubectl using the command from the outputs:

```sh
$(terraform output -raw configure_kubectl)
```

Or explicitly:

```sh
aws eks update-kubeconfig --name $(terraform output -raw cluster_name) --region $(terraform output -raw region)
```

## Verify the install

```sh
# Karpenter controller should be 2/2 Ready in the karpenter namespace.
kubectl get pods -n karpenter

# NodePool and EC2NodeClass should both be Ready.
kubectl get nodepool,ec2nodeclass
```

## Running a pod on x86 vs Graviton (the developer workflow)

The **only** spec change a developer makes to target an architecture is the `kubernetes.io/arch` nodeSelector:

```yaml
# x86
spec:
  nodeSelector:
    kubernetes.io/arch: amd64

# Graviton
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
```

Two ready-to-apply examples are in `examples/`:

```sh
# Schedule on x86 — Karpenter launches an amd64 Spot node (c/m/r family, gen >2)
kubectl apply -f examples/x86-deployment.yaml

# Schedule on Graviton — Karpenter launches an arm64 Spot node (e.g. c7g.large)
kubectl apply -f examples/arm64-deployment.yaml
```

Watch Karpenter provision the nodes:

```sh
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type --watch
```

You should see new nodes appear within ~60–90 s with the expected `arch` label and `capacity-type=spot`. After the deployment is deleted, Karpenter consolidates and removes the node within ~1 minute.

### Forcing On-Demand for a workload

Karpenter's default is "cheapest wins" — which is almost always Spot. To pin a workload to On-Demand:

```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
    karpenter.sh/capacity-type: on-demand
```

### A note on container images for arm64

Container images on arm64 must include an `arm64` manifest. Most official images on Docker Hub, ECR Public, and quay.io are already multi-arch — the examples here use `public.ecr.aws/nginx/nginx:1.27`, which is. For your own images, build with `docker buildx build --platform linux/amd64,linux/arm64`.

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `region` | `us-east-1` | AWS region |
| `cluster_name` | `opsfleet-poc` | EKS cluster name; also the value for the `karpenter.sh/discovery` tag |
| `kubernetes_version` | `1.33` | EKS Kubernetes minor version |
| `karpenter_version` | `1.5.0` | Karpenter Helm chart version (`oci://public.ecr.aws/karpenter/karpenter`) |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR |
| `azs_count` | `3` | Number of AZs to span |
| `tags` | `{}` | Extra tags merged onto every resource |

To bump the Karpenter or Kubernetes version, change the variable (or pass `-var`) and re-apply.

## Cleanup

```sh
# 1. Delete workloads so Karpenter-provisioned nodes drain
kubectl delete -f examples/

# 2. Destroy
terraform destroy
```

If `terraform destroy` hangs on a security group, ENI, or subnet because a Karpenter-launched node is still attached, drain remaining Karpenter nodes first:

```sh
kubectl get nodes -l karpenter.sh/nodepool
kubectl delete node -l karpenter.sh/nodepool
```

## Production hardening

This is a POC. Before promoting to production:

- **Remote state** — move Terraform state to S3 with DynamoDB locking
- **API endpoint** — disable `endpoint_public_access` or restrict via `endpoint_public_access_cidrs`
- **NAT** — set `single_nat_gateway = false` for per-AZ resilience
- **Observability** — enable EKS control-plane logging, Container Insights, and metrics scraping
- **Ingress** — install AWS Load Balancer Controller (or equivalent) — not included here
- **Policy** — PodSecurityAdmission baseline/restricted, plus Kyverno or OPA Gatekeeper
- **Tenancy** — separate NodePools per team/workload class with `limits` and `weight`
- **EBS CSI** — add the `aws-ebs-csi-driver` addon with IRSA/Pod Identity if you need PVCs
- **Right-size the system node group** — at minimum 1 node per AZ for the Karpenter controller's HA replicas
