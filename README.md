# MLOps CI/CD 2.0 — домашні завдання

The completed assignment is in [`lesson-3/`](lesson-3/README.md). It contains a
TorchScript MobileNetV2 model, fat and slim Docker images, reproducible metrics,
inference outputs and the comparison report.

Homework 2 is in [`eks-vpc-cluster/`](eks-vpc-cluster/README.md): separate VPC and
EKS Terraform roots connected through S3 remote state, with cost-safe teardown checks.

Homework 3 is implemented in branch `lesson-7`. Its Terraform configuration is in
[`terraform/argocd/`](terraform/argocd/), while Kubernetes manifests are kept in the
separate public GitOps repository
[`vikkrat/goit-argo`](https://github.com/vikkrat/goit-argo).

Фактичні результати запуску, діагностика scheduler та докази GitOps-синхронізації
наведені у [`terraform/argocd/report.md`](terraform/argocd/report.md).

## Homework 3: Argo CD through Terraform

### Prerequisites

- AWS CLI, Terraform, `kubectl`, and Helm are installed.
- The VPC and EKS from Homework 2 are running.
- `aws eks update-kubeconfig --region eu-north-1 --name mlops-hw2` succeeds.
- The public `goit-argo` repository exists and contains the `namespace/*` structure.

### Deploy

Create `terraform/argocd/backend.hcl` from the example and use the same S3 state
bucket that was created for Homework 2:

```bash
cd terraform/argocd
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

The `helm_release.argocd` resource creates namespace `infra-tools` and installs the
pinned `argo-cd` chart with custom values from `values/argocd-values.yaml`. Terraform
then creates an `ApplicationSet` that watches every directory matching
`namespace/*` in the GitOps repository.

### Verify Argo CD and GitOps synchronization

```bash
kubectl get pods -n infra-tools
kubectl get applicationsets -n infra-tools
kubectl get applications -n infra-tools
kubectl get deploy -n application
kubectl get pods -n application
```

Expected result: Argo CD pods are `Running`, applications are `Synced` and `Healthy`,
and `demo-nginx` has two ready replicas.

### Open the Argo CD UI

Read the one-time admin password without saving it to Git:

```bash
kubectl -n infra-tools get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode
```

In another terminal, start a local tunnel:

```bash
kubectl -n infra-tools port-forward svc/argocd-server 8080:443
```

Open <http://localhost:8080>, log in as `admin`, and use the password printed above.
The service is `ClusterIP`, so no public AWS load balancer is created.

### Verify the demo application

```bash
kubectl -n application port-forward deployment/demo-nginx 8081:80
```

Open <http://localhost:8081>. The standard Nginx page confirms that the GitOps
deployment works.

### Change flow

Any commit pushed to a directory under `namespace/*` in `goit-argo` is detected by
the ApplicationSet. Automated sync applies the change; `selfHeal` corrects manual
drift and `prune` removes Kubernetes objects deleted from Git.

### Фактичний результат

Перевірено в AWS `eu-north-1`: дві EKS nodes `Ready`, усі Argo CD pod-и
`Running`, обидві Applications `Synced/Healthy`, Nginx Deployment `2/2`, HTTP
через port-forward - `200`.

![Успішний EKS та GitOps-деплой](terraform/argocd/assets/01-eks-argocd-gitops-healthy.png)

![EKS cluster Active в AWS Console](terraform/argocd/assets/02-eks-cluster-active.png)

![Публічний GitOps repository](terraform/argocd/assets/03-gitops-repository.png)

![Terraform у гілці lesson-7](terraform/argocd/assets/04-lesson-7-terraform.png)

### Фінальне очищення AWS

Після фіксації результатів Argo CD, EKS, обидві node groups, VPC, NAT Gateway,
Elastic IP та versioned Terraform state bucket видалено. Додатково видалено
старий навчальний ECR repository `nginx-repo`. Фінальна перевірка показала нуль
активних або зупинених EC2, EKS clusters, NAT, EIP, EBS, Load Balancers, ASG,
RDS, ECR, non-default VPC, S3 buckets і Route53 zones.

![Фінальний AWS cost-safety audit](terraform/argocd/assets/05-final-aws-cleanup.jpg)

### Cost-safe teardown

Delete Argo CD first, then EKS, and finally VPC. Never delete VPC first because EKS
and its network interfaces depend on it.

```bash
cd terraform/argocd
terraform destroy

cd ../../eks-vpc-cluster/eks
terraform destroy

cd ../vpc
terraform destroy
```

Teardown completed on 24 August 2026. The final audit screenshot above is the
evidence that the homework infrastructure and storage were removed.
