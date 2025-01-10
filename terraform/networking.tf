resource "aws_vpc" "aws_vpc" {
	cidr_block = "10.0.0.0/16"

	tags = {
		Name = data.external.env.result["SHORT_APP_NAME"]
	}
}

locals {
	network_count = 1
}

resource "aws_subnet" "aws_subnet_public" {
	count = local.network_count
	vpc_id = aws_vpc.aws_vpc.id
	cidr_block = "10.0.${count.index + 1}.0/24"
	availability_zone = "${data.external.env.result["AWS_REGION"]}${jsondecode(format("\"\\u%04x\"", 97 + count.index))}"
	map_public_ip_on_launch = true

	tags = {
		Name = "${data.external.env.result["SHORT_APP_NAME"]}-public-${data.external.env.result["AWS_REGION"]}${jsondecode(format("\"\\u%04x\"", 97 + count.index))}"
		"kubernetes.io/role/elb" = 1
	}
}

resource "aws_subnet" "aws_subnet_private" {
	count = max(local.network_count, 2)
	vpc_id = aws_vpc.aws_vpc.id
	cidr_block = "10.0.${count.index + 3}.0/24"
	availability_zone = "${data.external.env.result["AWS_REGION"]}${jsondecode(format("\"\\u%04x\"", 97 + count.index))}"
	map_public_ip_on_launch = false

	tags = {
		Name = "${data.external.env.result["SHORT_APP_NAME"]}-private-${data.external.env.result["AWS_REGION"]}${jsondecode(format("\"\\u%04x\"", 97 + count.index))}"
	}
}

resource "aws_internet_gateway" "aws_internet_gateway" {
	vpc_id = aws_vpc.aws_vpc.id

	tags = {
		Name = "exch-gr-internet-gateway"
	}
}

# Elastic IPs for use in the NAT gateway to provide internet access

resource "aws_eip" "aws_eip_nat" {
	count = local.network_count
	vpc = true
	depends_on = [aws_internet_gateway.aws_internet_gateway]

	tags = {
		Name = "${data.external.env.result["SHORT_APP_NAME"]}-${data.external.env.result["AWS_REGION"]}${jsondecode(format("\"\\u%04x\"", 97 + count.index))}"
	}
}

# Elastic IPs for use in the NLB

resource "aws_eip" "aws_eip_nlb" {
	count = local.network_count
	vpc = true
	depends_on = [aws_internet_gateway.aws_internet_gateway]

	tags = {
		Name = "${data.external.env.result["SHORT_APP_NAME"]}-nlb-${data.external.env.result["AWS_REGION"]}${jsondecode(format("\"\\u%04x\"", 97 + count.index))}"
	}
}

resource "aws_nat_gateway" "aws_nat_gateway" {
	count = local.network_count
	subnet_id = aws_subnet.aws_subnet_public[count.index].id
	connectivity_type = "public"
	allocation_id = aws_eip.aws_eip_nat[count.index].id
	depends_on = [aws_internet_gateway.aws_internet_gateway]

	tags = {
		Name = "${data.external.env.result["SHORT_APP_NAME"]}-nat-gateway-${data.external.env.result["AWS_REGION"]}${jsondecode(format("\"\\u%04x\"", 97 + count.index))}"
	}
}

resource "aws_route_table" "aws_route_table_public" {
	vpc_id = aws_vpc.aws_vpc.id

	tags = {
		Name = "${data.external.env.result["SHORT_APP_NAME"]}-public"
	}
}

resource "aws_route" "aws_route_public" {
	destination_cidr_block = "0.0.0.0/0"
	route_table_id = aws_route_table.aws_route_table_public.id
	gateway_id = aws_internet_gateway.aws_internet_gateway.id
}

resource "aws_route_table_association" "aws_route_table_association_public" {
	count = local.network_count
	route_table_id = aws_route_table.aws_route_table_public.id
	subnet_id = aws_subnet.aws_subnet_public[count.index].id
}

resource "aws_route_table" "aws_route_table_private" {
	count = local.network_count
	vpc_id = aws_vpc.aws_vpc.id

	tags = {
		Name = "${data.external.env.result["SHORT_APP_NAME"]}-private-${data.external.env.result["AWS_REGION"]}${jsondecode(format("\"\\u%04x\"", 97 + count.index))}"
	}
}

resource "aws_route" "aws_route_private" {
	count = local.network_count
	destination_cidr_block = "0.0.0.0/0"
	route_table_id = aws_route_table.aws_route_table_private[count.index].id
	nat_gateway_id = aws_nat_gateway.aws_nat_gateway[count.index].id
}

resource "aws_route_table_association" "aws_route_table_association_private" {
	count = max(local.network_count, 2)
	route_table_id = aws_route_table.aws_route_table_private[min(count.index, local.network_count - 1)].id
	subnet_id = aws_subnet.aws_subnet_private[count.index].id
}

resource "aws_security_group" "aws_security_group" {
	name = data.external.env.result["SHORT_APP_NAME"]
	vpc_id = aws_vpc.aws_vpc.id

	ingress {
		protocol  = "tcp"
		from_port = 443
		to_port   = data.external.env.result["CONTAINER_PORT"]
		cidr_blocks = ["0.0.0.0/0"]
	}

	ingress {
		protocol  = "udp"
		from_port = 443
		to_port   = data.external.env.result["CONTAINER_PORT"]
		cidr_blocks = ["0.0.0.0/0"]
	}

	# postgres rds aurora

	ingress {
		protocol    = "tcp"
		from_port   = data.external.env.result["DATABASE_PORT"]
		to_port     = data.external.env.result["DATABASE_PORT"]
		cidr_blocks = aws_subnet.aws_subnet_private.*.cidr_block
	}

	egress {
		protocol  = "tcp"
		from_port = data.external.env.result["DATABASE_PORT"]
		to_port   = data.external.env.result["DATABASE_PORT"]
		cidr_blocks = aws_subnet.aws_subnet_private.*.cidr_block
	}
}

output "elastic-ip-allocation-ids-nlb" {
	value = join(",", aws_eip.aws_eip_nlb.*.allocation_id)
}
