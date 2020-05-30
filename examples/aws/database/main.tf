#------------------------------------------------------------------------------
# RDS - DATABASE RESOURCES
#------------------------------------------------------------------------------

resource "aws_db_subnet_group" "tfe" {
  name_prefix = "${var.namespace}-db-zone"
  description = "${var.namespace}-db-subnet-group"
  subnet_ids  = var.subnet_ids

  tags = merge(
    {
      Name  = "${var.namespace}-tfe-db-subnet-group"
    },
    var.common_tags,
  )
}

resource "aws_db_instance" "tfe" {
  identifier                = "${var.namespace}-tfe-db-instance"
  engine                    = "postgres"
  engine_version            = var.rds_engine_version
  instance_class            = var.database_instance_class
  allocated_storage         = var.database_storage
  storage_type              = "gp2" # [pp]
  # storage_encrypted         = true
  # kms_key_id                = var.kms_key_arn != "" ? var.kms_key_arn : ""

  name                      = var.database_name
  username                  = var.database_username
  password                  = var.database_pwd

  vpc_security_group_ids    = [var.vpc_security_group_ids]
  db_subnet_group_name      = aws_db_subnet_group.tfe.id

  multi_az                  = var.database_multi_az

  final_snapshot_identifier = "${var.namespace}-db-instance-final-snapshot"
  # [pp] changes
  skip_final_snapshot       = "true"
  backup_retention_period   = "0" # disable backup

  tags = merge(
    {
      Name  = "${var.namespace}-tfe-rds"
    },
    var.common_tags,
  )

}
