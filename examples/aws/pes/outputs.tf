output "tfe_fqdn" {
  value = "${aws_route53_record.pes.fqdn}"
}

# output "tfe_public_ip" {
#   value = "${aws_instance.primary.*.public_ip}"
# }

# output "tfe_private_ip" {
#   value = "${aws_instance.primary.*.private_ip}"
# }

# output "tfe_public_dns" {
#   value = "${aws_instance.primary.*.public_dns}"
# }

# output "tfe_private_dns" {
#   value = "${aws_instance.primary.*.private_dns}"
# }
