# Inputs with defaults. Override with: terraform apply -var region=us-east-1
# AWS region for everything.
variable "region" {
  type    = string
  default = "ap-southeast-1"
}

# Name of the cluster and the VPC.
variable "cluster_name" {
  type    = string
  default = "gitops-demo"
}

# Kubernetes version (1.30+ needed for the admission policies).
variable "kubernetes_version" {
  type    = string
  default = "1.34"
}
