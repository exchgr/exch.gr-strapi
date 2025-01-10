resource "random_password" "random_password" {
	length = 64
	special = false
}

resource "aws_db_subnet_group" "aws_db_subnet_group" {
	name = data.external.env.result["SHORT_APP_NAME"]

	subnet_ids = concat(
		aws_subnet.aws_subnet_private.*.id,
		aws_subnet.aws_subnet_public.*.id,
	)
}

resource "aws_rds_cluster" "aws_rds_cluster" {
	cluster_identifier = data.external.env.result["SHORT_APP_NAME"]
	engine = "aurora-postgresql"
	storage_encrypted = true
	apply_immediately = true

	# credentials
	database_name = data.external.env.result["DATABASE_NAME"]
	master_username = data.external.env.result["DATABASE_USERNAME"]
	master_password = random_password.random_password.result

	# logs
	enabled_cloudwatch_logs_exports = ["postgresql"]

	# networking
	db_subnet_group_name = aws_db_subnet_group.aws_db_subnet_group.name
	vpc_security_group_ids = [aws_security_group.aws_security_group.id]

	final_snapshot_identifier = data.external.env.result["DATABASE_FINAL_SNAPSHOT_IDENTIFIER"]
}

resource "aws_rds_cluster_instance" "aws_rds_cluster_instance" {
	count = 1
	identifier = "${data.external.env.result["SHORT_APP_NAME"]}-${count.index}"
	cluster_identifier = aws_rds_cluster.aws_rds_cluster.id
	instance_class = "db.t4g.medium"
	engine = aws_rds_cluster.aws_rds_cluster.engine
	engine_version = aws_rds_cluster.aws_rds_cluster.engine_version
	ca_cert_identifier = "rds-ca-ecc384-g1"
	apply_immediately = true
	publicly_accessible = true
}

output "aws_rds_cluster_endpoint" {
	value = aws_rds_cluster.aws_rds_cluster.endpoint
}
