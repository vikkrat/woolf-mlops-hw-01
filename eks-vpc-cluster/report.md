# Звіт до домашнього завдання №2

## Що реалізовано

- окремий Terraform root `vpc/` на офіційному модулі `terraform-aws-modules/vpc/aws`;
- VPC `10.42.0.0/16`, дві public і дві private subnet у двох Availability Zones;
- один NAT Gateway як дешевший варіант для короткочасної лабораторної роботи;
- окремий Terraform root `eks/` на офіційному модулі `terraform-aws-modules/eks/aws`;
- читання `vpc_id` і private subnet через `terraform_remote_state` із S3;
- EKS 1.33 та керовані add-ons `vpc-cni`, `kube-proxy`, `coredns`;
- дві EKS managed node groups по одному `t3.small`;
- `cpu-nodes` має label `workload=cpu`;
- `gpu-nodes` імітує окремий GPU workload pool через label
  `workload=gpu-simulated` і taint `dedicated=gpu-workload:NoSchedule`.

Справжній GPU instance навмисно не використовувався, щоб не створювати значні
витрати AWS. Ізоляція workload відповідає дозволеній у завданні симуляції.

## Перевірка

Після `terraform apply` виконано:

```bash
aws eks update-kubeconfig --region eu-north-1 --name mlops-hw2
kubectl get nodes -L workload
kubectl get nodes -l workload=gpu-simulated \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,TAINTS:.spec.taints'
```

Результат: два worker nodes мають статус `Ready`; один належить CPU pool, другий
має GPU-simulated label і `NoSchedule` taint.

![kubectl: два Ready nodes](assets/01-kubectl-ready-nodes.png)

AWS Console також підтвердила:

- EKS cluster `mlops-hw2`: `Active`, cluster health issues: `0`;
- `cpu-nodes` і `gpu-nodes`: `Active`, desired size: `1` кожна;
- VPC `mlops-hw2`: `Available`, CIDR `10.42.0.0/16`.

![EKS cluster Active](assets/02-eks-cluster-active.png)

![EKS managed node groups](assets/03-eks-node-groups-active.png)

![VPC Available](assets/04-vpc-available.png)

## Контроль витрат і очищення

Після збереження доказів ресурси необхідно видаляти саме в такому порядку:

1. EKS і managed node groups (`terraform destroy` у `eks/`).
2. VPC, NAT Gateway та Elastic IP (`terraform destroy` у `vpc/`).
3. Версії state-файлів і спеціально створений S3 backend bucket.
4. Фінальна AWS CLI-перевірка відсутності EKS, EC2, NAT Gateway, Elastic IP і VPC
   з тегом `Homework=2`.

## Фінальний результат очищення

Після збереження доказів виконано:

- EKS Terraform destroy: `43 destroyed`;
- VPC Terraform destroy: `19 destroyed`;
- видалено всі 24 версії об'єктів спеціального S3 state bucket, після чого
  видалено сам bucket;
- AWS CLI повернула `[]` для EKS clusters, активних EC2 instances, billable NAT
  Gateways, Elastic IP, load balancers, non-default VPC та homework state bucket.

![Фінальний CLI cost audit](assets/05-final-cost-audit-empty.png)

У консолі AWS EKS відображається `Clusters (0)`:

![EKS clusters zero](assets/06-eks-clusters-zero.png)

У VPC Console залишився лише стандартний `default VPC`; навчальний
`mlops-hw2` видалено:

![Only default VPC remains](assets/07-only-default-vpc-remains.png)
