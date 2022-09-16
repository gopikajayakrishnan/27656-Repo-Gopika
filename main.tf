provider "aws" {
  region = var.aws_region
}

# Create Key

resource "tls_private_key" task1_p_key  {
  algorithm = "RSA"
}


resource "aws_key_pair" "task1-key" {
  key_name    = var.key_name
  public_key = tls_private_key.task1_p_key.public_key_openssh
  }

resource "local_file" "private_key" {
  depends_on = [
    tls_private_key.task1_p_key,
  ]
  content  = tls_private_key.task1_p_key.private_key_pem
  filename = "webserver.pem"
}

# data source to get list AMI

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}


# Creation of Bastion-prod server

# create VPC

resource "aws_vpc" "My_VPC" {
  cidr_block          = "192.168.0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
 
tags = {
    Name = "My VPC"
}
}

# Create Subnet

resource "aws_subnet" "My_VPC_Subnet" {
  vpc_id                  = aws_vpc.My_VPC.id
  cidr_block              = "192.168.0.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = "us-east-1a"
tags = {
   Name = "My VPC Subnet"
}
}
resource "aws_subnet" "My_VPC_Subnet2" {
  vpc_id                  = aws_vpc.My_VPC.id
  cidr_block              = "192.168.1.0/24"
  availability_zone       = "us-east-1b"
tags = {
   Name = "My VPC Subnet"
}
}

# Crete Internet Gateway
resource "aws_internet_gateway" "My_VPC_GW" {
 vpc_id = aws_vpc.My_VPC.id
 tags = {
        Name = "My VPC Internet Gateway"
}
}

# Create Route table 
resource "aws_route_table" "My_VPC_route_table" {
 vpc_id = aws_vpc.My_VPC.id
 tags = {
        Name = "My VPC Route Table"
}
}

resource "aws_route" "My_VPC_internet_access" {
  route_table_id         = aws_route_table.My_VPC_route_table.id
  destination_cidr_block =  "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.My_VPC_GW.id
}

resource "aws_route_table_association" "My_VPC_association" {
  subnet_id      = aws_subnet.My_VPC_Subnet.id
  route_table_id = aws_route_table.My_VPC_route_table.id
}

# Security Group for Bastion prod server

resource "aws_security_group" "only_ssh_basiton" {
  depends_on=[aws_subnet.My_VPC_Subnet]
  name        = "only_ssh_basiton"
  vpc_id      =  aws_vpc.My_VPC.id

ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "only_ssh_basiton"
  }
}


# Create Sg for Batchingestion Server
resource "aws_security_group" "allow_http" {
  name        = "allow_http"
   vpc_id     = aws_vpc.My_VPC.id
ingress {

    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
tags = {
    Name = "allow_http"
  }
}


resource "aws_eip" "gopika_ip" {
  vpc              = true
  public_ipv4_pool = "amazon"
}

# NAT Gateway

resource "aws_nat_gateway" "gopika27656" {
    depends_on=[aws_eip.gopika_ip]
  allocation_id = aws_eip.gopika_ip.id
  subnet_id     = aws_subnet.My_VPC_Subnet.id
tags = {
    Name = "gopikagw"
  }
}

// Route table for NAT in private subnet

resource "aws_route_table" "private_subnet_route_table" {
      depends_on=[aws_nat_gateway.gopika27656]
  vpc_id = aws_vpc.My_VPC.id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.gopika27656.id
  }



  tags = {
    Name = "private_subnet_route_table"
  }
}


resource "aws_route_table_association" "private_subnet_route_table_association" {
  depends_on = [aws_route_table.private_subnet_route_table]
  subnet_id      = aws_subnet.My_VPC_Subnet2.id
  route_table_id = aws_route_table.private_subnet_route_table.id
}


# Instance for Bastion-prod

resource "aws_instance" "BASTION" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.My_VPC_Subnet.id
  vpc_security_group_ids = [ aws_security_group.only_ssh_basiton.id ]
  key_name = var.key_name

  tags = {
    Name = "bastion-prod"
    }
}

# Instance for Batchingestion-prod

  resource "aws_instance" "batchingestion" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "m5.2xlarge"
  subnet_id = aws_subnet.My_VPC_Subnet.id
  vpc_security_group_ids = [ aws_security_group.allow_http.id,aws_security_group.only_ssh_basiton.id  ]
   key_name = var.key_name


  tags = {
    Name = "batchingestion-prod"
    }
}

# Output

output "Instance_ID_Bastion-prod" {
  description = "EC2 instance ID"
  value = aws_instance.BASTION.id
}

output "Instance_ID_Batchingestion-prod" {
  description = "EC2 instance ID"
  value = aws_instance.batchingestion.id
}


# Creation of Jenkins-prod server 

resource "aws_instance" "my-ec2" {
  ami = data.aws_ami.amazon_linux_2.id
  instance_type = var.ec2_instance_type
  availability_zone = "us-east-1a"
  key_name = var.key_name
  user_data            = file("install_jenkins.sh")

  network_interface { 
     device_index         = 0
     network_interface_id = aws_network_interface.my_jenkins_network_int.id
   }
	
}




resource "aws_vpc" "my_jenkins_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
      Name = "dev-vpc"
  }
}

# Subnet

resource "aws_subnet" "my_jenkins_subnet" {
  vpc_id = aws_vpc.my_jenkins_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    "Name" = "dev-subnet"
  }
}

# Internet gateway

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.my_jenkins_vpc.id

  tags = {
    Name = "dev-gw"
  }
}

# Create Route Table

resource "aws_route_table" "my_rt" {
  vpc_id = aws_vpc.my_jenkins_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "dev-rt"
  }
}

# Association between a route table and a subnet

resource "aws_route_table_association" "a_rt_subnet" {
  subnet_id      = aws_subnet.my_jenkins_subnet.id
  route_table_id = aws_route_table.my_rt.id
}

#  Create Security Group 

resource "aws_security_group" "my_jenkins_sg" {
  name        = "allow_my_webapp"
  description = "Allow webapp inbound traffic"
  vpc_id      = aws_vpc.my_jenkins_vpc.id

  ingress {
    description      = "HTTPS Access"
    from_port        = 8080  //
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] 
    ipv6_cidr_blocks = ["::/0"]
  }

     ingress {
     description      = "HTTP Access"
     from_port        = 80
     to_port          = 80
     protocol         = "tcp"
     cidr_blocks      = ["0.0.0.0/0"]
     ipv6_cidr_blocks = ["::/0"]
   }

    ingress {
    description      = "SSH Access"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] 
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1" // -1 means All/Any protocols
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "dev-sg"
  }
}

# Create Network Interface

resource "aws_network_interface" "my_jenkins_network_int" {
  subnet_id       = aws_subnet.my_jenkins_subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.my_jenkins_sg.id,aws_security_group.only_ssh_basiton.id ]

  tags = {
    Name = "my-network-interface"
  }
/*
  attachment {
    instance     = aws_instance.my-ec2.id
    device_index = 1
  }
*/
}

//Public IP
resource "aws_eip" "lb" {
  instance = aws_instance.my-ec2.id
  vpc      = true
}

# Output of EC2 Private IP
# Instance ID of Jenkins prod
output "Instance_ID_Jenkins-prod" {
  description = "EC2 instance ID"
  value = aws_instance.my-ec2.id
}

# Output of EC2 Private IP
output "Private_IP_Jenkins-prod" {
  description = "Private IP of the EC2 instance"
  value = aws_instance.my-ec2.private_ip
}

# Output of EC2 Public IP

output "Public_IP_Jenkins-prod" {
  description = "Public IP of the EC2 instance"
  value = aws_instance.my-ec2.public_ip
}

# print the url of the jenkins server
output "jenkins-prod_endpoint" {
  value = join ("", ["http://", aws_instance.my-ec2.public_ip, ":", "8080"])
}




