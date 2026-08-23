locals {
  common_tags = {
    Project    = var.cluster_name
    ManagedBy  = "Terraform"
    Homework   = "2"
    AutoDelete = "true"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnets

  # Базові керовані add-ons, без яких worker nodes не можуть повноцінно
  # працювати: CNI надає мережу Pod-ам, kube-proxy реалізує Service networking,
  # а CoreDNS забезпечує DNS усередині кластера.
  addons = {
    vpc-cni = {
      before_compute = true
      most_recent    = true
    }
    kube-proxy = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
  }

  # Обидві групи використовують маленькі CPU instances. Друга імітує окремий
  # GPU/workload pool через label і taint, не створюючи дорогий GPU instance.
  eks_managed_node_groups = {
    cpu-nodes = {
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1

      labels = {
        workload = "cpu"
      }
    }

    gpu-nodes = {
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1

      labels = {
        workload = "gpu-simulated"
      }

      taints = {
        dedicated = {
          key    = "dedicated"
          value  = "gpu-workload"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }
}
