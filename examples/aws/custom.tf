resource "aws_key_pair" "ec2_key" {
  key_name   = "${var.namespace}-ec2-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCjOXiqjoBMlfCBvmG6BcUGPv1q+YqNYLHlm6X18Frue+Yf2zG/56pMWtSoPbHKB+Nul0VNpANuOyt3qsEU+HtZz9MMTBiWL6kGH6S0saLMp7EpcZaib/Qxfkl1By6JnOwr6w7eW+XE4TXHRdBKaRWW4J52KdhlPXAeMFeSDL3qnZWaP7tIyKTQzdDXu0rSJIBpcYCVCQ5BkshWNvoVpDH0dH9r4ayLrzgnNzQHyqVFASU3DxqIAqrC3JflAz1aUWiwXhDJeZU3w6eDWvYxOAm+Z2vP5oiX/pqbYMlCUlPrsU5+6828kDQ5uQaZiCnSi2Bj3BDqpJngiVvyicJgvhW9 pephan@Mac-mini.local"

  # public_key = "${file("~/.ssh/id_rsa.pub")}"
  # public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDhhEKJBWpUOHomxK6+8IJ7awT27/HfwG80PK+SrwAFaM4WhTg526etf5ksDpyjRQd3j1XDX9jVYUT5vTIaQ/YhqNVyaLM2ayY6GhAR+R+PIdpK1bhvfMvp6Rgsbii8PsD1HnKEJTOJayrhVY7W95mTUIGmCAWiIN1qrR04ffpfxNJdYcZdLbXu6DnT/EKJS9hQRgWLjQYSmJ0sOy4LeW7NqbDoOEunfzv8bX2dGbE4zn+ZpFSOAUC/VQTyxdkRPGiv3ocJyz+qbbSf7qCxYW61UX3K6Zdn/0ND8vqpl9xMvejPSk/4mIMNGuSrO8i/SzbgcM5ulS09KIw7GMoD6rwF peterphan@Peters-MacBook-Pro.local"
}
