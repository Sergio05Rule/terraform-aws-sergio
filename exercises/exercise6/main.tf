terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10.0"
    }
    # null = {
    #   source  = "hashicorp/null"
    #   version = ">= 3.2.0"
    # }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "aws_availability_zones" "available" {}

locals {
  name        = "cloudacademydevops"
  environment = "demo"
  k8s_version = "1.27"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

#====================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">= 5.0.0, < 6.0.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  manage_default_network_acl    = true
  manage_default_route_table    = true
  manage_default_security_group = true

  default_network_acl_tags = {
    Name = "${local.name}-default"
  }

  default_route_table_tags = {
    Name = "${local.name}-default"
  }

  default_security_group_tags = {
    Name = "${local.name}-default"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Name        = "${local.name}-eks"
    Environment = local.environment
  }
}

#====================================
resource "aws_iam_role" "eks_cluster_role" {
  name = "cloudacademydevops-eks-2025-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::664185728766:user/sergio.abascia@aspectinnovate.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSVPCResourceController" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = ">= 19.15.0"

  cluster_name    = "${local.name}-eks-2025"
  cluster_version = local.k8s_version

  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_iam_role = false
  iam_role_arn    = aws_iam_role.eks_cluster_role.arn

  eks_managed_node_groups = {
    default = {
      use_custom_launch_template = false

      instance_types = ["m5.large"]
      capacity_type  = "ON_DEMAND" # "SPOT" # useful for demos and dev purposes

      disk_size = 10

      min_size     = 2
      max_size     = 2
      desired_size = 2
    }
  }

  tags = {
    Name        = "${local.name}-eks"
    Environment = local.environment
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name

}

#====================================
# todo comment at first apply 
# after first aplly run -  Mappa manualmente il tuo IAM user in aws-auth
# aws eks update-kubeconfig --region eu-central-1 --name cloudacademydevops-eks-2025
# applica aws-auth.yaml
# kubectl apply -f aws-auth.yaml
# inserire my iam user as access to the cluster (GUI), since questo viene gerenato da un role ad hoc e questo e' l unico ruolo mappato nel aws-auth (file interno a kubernetes)
# terraform apply (2)


module "eks_aws_auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = ">= 19.15.0"

  depends_on = [module.eks]

  manage_aws_auth_configmap = true

  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::664185728766:user/sergio.abascia@aspectinnovate.com"
      username = "sergio.abascia@aspectinnovate.com"
      groups   = ["system:masters"]
    }
  ]

  # potrebbe non servire, ma lo lascio per sicurezza
  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.eks_cluster_role.arn
      username = "cloudacademydevops-eks-admin"
      groups   = ["system:masters"]
    }
  ]
  
  providers = {
    kubernetes = kubernetes
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
    
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      }
  }
}

resource "helm_release" "nginx_ingress" {
  name = "nginx-ingress"

  repository       = "https://helm.nginx.com/stable"
  chart            = "nginx-ingress"
  namespace        = "nginx-ingress"
  create_namespace = true


  set = [
  {
    name  = "service.type"
    value = "ClusterIP"
  },
  {
    name  = "controller.service.name"
    value = "nginx-ingress-controller"
  }]
}

resource "terraform_data" "deploy_app" {
  triggers_replace = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.module
    command     = <<EOT
      echo deploying app...
      ./k8s/app.install.sh
    EOT
  }

  depends_on = [
    helm_release.nginx_ingress,
    module.eks_aws_auth
  ]
}
