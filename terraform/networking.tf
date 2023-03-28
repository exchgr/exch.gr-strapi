resource "aws_vpc" "exch-gr" {
	cidr_block = "10.0.0.0/16"

	tags = {
		Name = "exch-gr"
	}
}

resource "aws_subnet" "exch-gr-public-us-east-1a" {
	vpc_id = aws_vpc.exch-gr.id
	cidr_block = "10.0.1.0/24"
	availability_zone = "us-east-1a"
	map_public_ip_on_launch = true

	tags = {
		Name = "exch-gr-public-us-east-1a"
	}
}

resource "aws_subnet" "exch-gr-public-us-east-1b" {
	vpc_id = aws_vpc.exch-gr.id
	cidr_block = "10.0.2.0/24"
	availability_zone = "us-east-1b"
	map_public_ip_on_launch = true

	tags = {
		Name = "exch-gr-public-us-east-1b"
	}
}

resource "aws_subnet" "exch-gr-private-us-east-1a" {
	vpc_id = aws_vpc.exch-gr.id
	cidr_block = "10.0.3.0/24"
	availability_zone = "us-east-1a"
	map_public_ip_on_launch = false

	tags = {
		Name = "exch-gr-private-us-east-1a"
	}
}

resource "aws_subnet" "exch-gr-private-us-east-1b" {
	vpc_id = aws_vpc.exch-gr.id
	cidr_block = "10.0.4.0/24"
	availability_zone = "us-east-1b"
	map_public_ip_on_launch = false

	tags = {
		Name = "exch-gr-private-us-east-1b"
	}
}

resource "aws_internet_gateway" "exch-gr-internet-gateway" {
	vpc_id = aws_vpc.exch-gr.id

	tags = {
		Name = "exch-gr-internet-gateway"
	}
}

resource "aws_eip" "exch-gr-us-east-1a" {
	vpc = true
	depends_on = [aws_internet_gateway.exch-gr-internet-gateway]

	tags = {
		Name = "exch-gr-us-east-1a"
	}
}

resource "aws_eip" "exch-gr-us-east-1b" {
	vpc = true
	depends_on = [aws_internet_gateway.exch-gr-internet-gateway]

	tags = {
		Name = "exch-gr-us-east-1b"
	}
}

resource "aws_nat_gateway" "exch-gr-nat-gateway-us-east-1a" {
	subnet_id = aws_subnet.exch-gr-public-us-east-1a.id
	connectivity_type = "public"
	allocation_id = aws_eip.exch-gr-us-east-1a.id
	depends_on = [aws_internet_gateway.exch-gr-internet-gateway]

	tags = {
		Name = "exch-gr-nat-gateway-us-east-1a"
	}
}

resource "aws_nat_gateway" "exch-gr-nat-gateway-us-east-1b" {
	subnet_id = aws_subnet.exch-gr-public-us-east-1b.id
	connectivity_type = "public"
	allocation_id = aws_eip.exch-gr-us-east-1b.id
	depends_on = [aws_internet_gateway.exch-gr-internet-gateway]

	tags = {
		Name = "exch-gr-nat-gateway-us-east-1b"
	}
}

resource "aws_route_table" "exch-gr-public" {
	vpc_id = aws_vpc.exch-gr.id

	tags = {
		Name = "exch-gr-public"
	}
}

resource "aws_route" "exch-gr-public" {
	destination_cidr_block = "0.0.0.0/0"
	route_table_id = aws_route_table.exch-gr-public.id
	gateway_id = aws_internet_gateway.exch-gr-internet-gateway.id
}

resource "aws_route_table_association" "exch-gr-public-us-east-1a" {
	route_table_id = aws_route_table.exch-gr-public.id
	subnet_id = aws_subnet.exch-gr-public-us-east-1a.id
}

resource "aws_route_table_association" "exch-gr-public-us-east-1b" {
	route_table_id = aws_route_table.exch-gr-public.id
	subnet_id = aws_subnet.exch-gr-public-us-east-1b.id
}

resource "aws_route_table" "exch-gr-private-us-east-1a" {
	vpc_id = aws_vpc.exch-gr.id

	tags = {
		Name = "exch-gr-private-us-east-1a"
	}
}

resource "aws_route_table" "exch-gr-private-us-east-1b" {
	vpc_id = aws_vpc.exch-gr.id

	tags = {
		Name = "exch-gr-private-us-east-1b"
	}
}

resource "aws_route" "exch-gr-private-us-east-1a" {
	destination_cidr_block = "0.0.0.0/0"
	route_table_id = aws_route_table.exch-gr-private-us-east-1a.id
	nat_gateway_id = aws_nat_gateway.exch-gr-nat-gateway-us-east-1a.id
}

resource "aws_route" "exch-gr-private-us-east-1b" {
	destination_cidr_block = "0.0.0.0/0"
	route_table_id = aws_route_table.exch-gr-private-us-east-1b.id
	nat_gateway_id = aws_nat_gateway.exch-gr-nat-gateway-us-east-1b.id
}

resource "aws_route_table_association" "exch-gr-private-us-east-1a" {
	route_table_id = aws_route_table.exch-gr-private-us-east-1a.id
	subnet_id = aws_subnet.exch-gr-private-us-east-1a.id
}

resource "aws_route_table_association" "exch-gr-private-us-east-1b" {
	route_table_id = aws_route_table.exch-gr-private-us-east-1b.id
	subnet_id = aws_subnet.exch-gr-private-us-east-1b.id
}

resource "aws_security_group" "exch-gr" {
	name = "exch-gr"
	vpc_id = aws_vpc.exch-gr.id

	ingress {
		protocol  = "tcp"
		from_port = 443
		to_port   = 1337
		cidr_blocks = ["0.0.0.0/0"]
	}

	ingress {
		protocol  = "udp"
		from_port = 443
		to_port   = 1337
		cidr_blocks = ["0.0.0.0/0"]
	}

	# postgres rds aurora

	ingress {
		protocol    = "tcp"
		from_port   = 5432
		to_port     = 5432
		cidr_blocks = [
			aws_subnet.exch-gr-private-us-east-1a.cidr_block,
			aws_subnet.exch-gr-private-us-east-1b.cidr_block,
		]
	}

	egress {
		protocol  = "tcp"
		from_port = 5432
		to_port   = 5432
		cidr_blocks = [
			aws_subnet.exch-gr-private-us-east-1a.cidr_block,
			aws_subnet.exch-gr-private-us-east-1b.cidr_block,
		]
	}
}
