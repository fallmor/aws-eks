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
  name        = "k8s-sg"
  description = "Security group to allow inbound/outbound traffic from the VPC"
  vpc_id      = aws_vpc.test-vpc.id
  depends_on  = [aws_vpc.test-vpc]
  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = "true"
  }
}

resource "aws_vpc" "test-vpc" {
  cidr_block       = "10.20.0.0/16"
  enable_dns_support = "true"
  enable_dns_hostnames = true
  tags = {
     "kubernetes.io/cluster/mor-cluster":"shared"
  }
}
data "aws_availability_zones" "available" {
  state = "available"
}

/*Subnets */
/* Internet gateway for the public subnet */
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.test-vpc.id
  tags = {
    Name = "k8s-igw"
  }
}

// eip for nat gateway
resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.igw]
}

//aws nat gw
resource "aws_nat_gateway" "nat" {
  //count         = length(data.aws_availability_zones.available.names)
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.pubsub[0].id
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    Name = "k8s-nat"
  }
}

resource "aws_subnet" "pubsub" {
  count                   = length(data.aws_availability_zones.available.names)
  vpc_id                  = aws_vpc.test-vpc.id
  cidr_block              = "10.20.${10 + count.index}.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  

  tags = {
    //Name = "PublicSubnet"
   "kubernetes.io/cluster/mor-cluster":"shared"
  }
}
resource "aws_subnet" "privsub" {
  count                   = length(data.aws_availability_zones.available.names)
  vpc_id                  = aws_vpc.test-vpc.id
  cidr_block              = "10.20.${20 + count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  

  tags = {
  //Name = "PrivateSubnet"
  "kubernetes.io/cluster/mor-cluster":"shared"
   "kubernetes.io/role/internal-elb":1
   "kubernetes.io/role/elb":1
  }
}

// Routing table for private subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.test-vpc.id
  tags = {
    Name = "private-route-table"

  }
}
// Routing table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.test-vpc.id
  tags = {
    Name = "public-route-table"
  }
}


// route for public subnet and private subnet

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}
resource "aws_route" "private_nat_gateway" {
  count                  = length(data.aws_availability_zones.available.names)
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}
// Route table associations
resource "aws_route_table_association" "public" {
  count          = length(data.aws_availability_zones.available.names)
  subnet_id      = aws_subnet.pubsub[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private" {
  count          = length(data.aws_availability_zones.available.names)
  subnet_id      = aws_subnet.privsub[count.index].id
  route_table_id = aws_route_table.private.id
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
resource "aws_iam_role_policy_attachment" "AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

module "my-cluster" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "mor-cluster"
  cluster_version = "1.17"
  subnets       = aws_subnet.privsub.*.id
  vpc_id          = aws_vpc.test-vpc.id
  cluster_iam_role_name = aws_iam_role.eks_cluster.arn

  worker_groups = [
    {
      spot_price          = "0.199"
      instance_type = "t3.micro"
      root_volume_type = "gp2"
      asg_desired_capacity = var.env == "prod" ? 3 : 0
      kubelet_extra_args  = "--node-labels=node.kubernetes.io/lifecycle=spot"
      asg_max_size  = 4
      additional_security_group_ids = [aws_security_group.eks-secgroup.id]
      workers_user_data = <<-EOF
            #!/bin/bash -ex
            exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
            curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh
            chmod 700 get_helm.sh
            ./get_helm.sh
            kubectl create ns	wordpress-cwi   
            helm -n wordpress-cwi install understood-zebu bitnami/wordpress  
            sleep 30
            export SERVICE_IP=$(kubectl get svc --namespace wordpress-cwi understood-zebu-wordpress --template "{{ range (index .status.loadBalancer.ingress 0) }}{{.}}{{ end }}") 
            echo "WordPress URL: http://$SERVICE_IP/" 
            echo "WordPress Admin URL: http://$SERVICE_IP/admin" 
            echo Username: user 
            echo Password: $(kubectl get secret --namespace wordpress-cwi understood-zebu-wordpress -o jsonpath="{.data.wordpress-password}" | base64 --decode) | tee -a /dev/tty
EOF
 
    }
  ]
}
