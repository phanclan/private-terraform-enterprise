output "tfe_fqdn" {
  value = "${module.pes.tfe_fqdn}"
}

# output "tfe_public_ip" {
#   value = "${module.pes.tfe_public_ip}"
# }

# output "tfe_private_ip" {
#   value = "${module.pes.tfe_private_ip}"
# }

# output "tfe_public_dns" {
#   value = "${module.pes.tfe_public_dns}"
# }

# output "tfe_private_dns" {
#   value = "${module.pes.tfe_private_dns}"
# }

output "db_endpoint" {
  value = "${module.database.db_endpoint}"
}
