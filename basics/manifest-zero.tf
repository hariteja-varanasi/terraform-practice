resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    instance_tenancy = "default"
    tags = {
        Name = "tf-vpc-example-zero"
        Environment = "dev"
        Project = "terraform-practice"
    }

}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "tf-igw-example-zero"
        Environment = "dev"
        Project = "terraform-practice"
    }
}

resource "aws_subnet" "subnet-0" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.0.0/20"
    availability_zone = "us-east-1a"
    tags = {
        Name = "tf-subnet-example-zero"
        Environment = "dev"
        Project = "terraform-practice"
    }
}

resource "aws_subnet" "subnet-1" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.16.0/20"
    availability_zone = "us-east-1b"
    tags = {
        Name = "tf-subnet-example-zero"
        Environment = "dev"
        Project = "terraform-practice"
    }
}

# Create Route Tables - public and private
    # Route associations subnet-0 into the public route table and then add a route to the internet gateway
    # Route associations subnet-1 into the private route table

# Public route table: subnet-0, with a default route to the internet gateway
resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }

    tags = {
        Name        = "tf-rt-public-example-zero"
        Environment = "dev"
        Project     = "terraform-practice"
    }
}

resource "aws_route_table_association" "public-subnet-0" {
    subnet_id      = aws_subnet.subnet-0.id
    route_table_id = aws_route_table.public.id
}

# Private route table: subnet-1, local VPC routing only (no internet route)
resource "aws_route_table" "private" {
    vpc_id = aws_vpc.main.id

    tags = {
        Name        = "tf-rt-private-example-zero"
        Environment = "dev"
        Project     = "terraform-practice"
    }
}

resource "aws_route_table_association" "private-subnet-1" {
    subnet_id      = aws_subnet.subnet-1.id
    route_table_id = aws_route_table.private.id
}