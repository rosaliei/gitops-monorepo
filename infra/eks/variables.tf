variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "cluster_name" {
  type    = string
  default = "gitops-demo"
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}
