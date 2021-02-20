data "aws_eks_cluster" "cluster" {
  name = module.my-cluster.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.my-cluster.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.9"
}

resource "aws_security_group" "eks-secgroup" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = aws_vpc.test-vpc.id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }

   egress {
    from_port = 0
    to_port   = 22
    protocol  = "-1"
  }
}

resource "aws_vpc" "test-vpc" {
  cidr_block       = "10.0.0.0/16"
  enable_dns_support = "true"
  enable_dns_hostnames = true
}
data "aws_availability_zones" "available" {
  state = "available"
}
resource "aws_subnet" "pubsub"  {
    vpc_id      = aws_vpc.test-vpc.id
    cidr_block = "10.0.4.0/25"
    map_public_ip_on_launch = "true"
    availability_zone = data.aws_availability_zones.available.names[0]
  }
  resource "aws_subnet" "privsub1"  {
    vpc_id      = aws_vpc.test-vpc.id
    cidr_block = "10.0.5.0/25"
    availability_zone = data.aws_availability_zones.available.names[1]
  }

// role for eks master

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster.name
}


module "my-cluster" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "mor-clusetr"
  cluster_version = "1.17"
  subnets       = [aws_subnet.pubsub.id, aws_subnet.privsub1.id]
  vpc_id          = aws_vpc.test-vpc.id
  cluster_iam_role_name = aws_iam_role.eks_cluster.arn
  worker_groups = [
    {
      spot_price          = "0.199"
      instance_type = "t3.micro"
      root_volume_type = "gp2"
      kubelet_extra_args  = "--node-labels=node.kubernetes.io/lifecycle=spot"
      asg_max_size  = 3
      additional_security_group_ids = [aws_security_group.eks-secgroup.id]
    }
  ]
}