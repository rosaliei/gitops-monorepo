# Minimal EKS cluster for running this repo in AWS.
# Cost warning: EKS + NAT gateway + 2 nodes cost money per hour. `terraform destroy` when done.
#
#   cd infra/eks && terraform init && terraform apply
#   aws eks update-kubeconfig --name gitops-demo --region <region>
#   ../../scripts/bootstrap.sh    # same ArgoCD bootstrap as on kind (skip the kind step)

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Use remote state in a team (S3 + DynamoDB lock or HCP Terraform):
  # backend "s3" { bucket = "my-tf-state" key = "gitops-demo/eks.tfstate" region = "ap-southeast-1" }
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

locals {
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
  tags = { project = "gitops-demo", managed-by = "terraform" }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name            = var.cluster_name
  cidr            = "10.0.0.0/16"
  azs             = local.azs
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # one NAT to keep the demo cheap; use one per AZ in production

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
  tags                = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access                   = true # restrict with endpoint_public_access_cidrs in real life
  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
    }
  }

  tags = local.tags
}
