availability_zones    = ["eu-central-1a", "eu-central-1b"]
cidr_block            = "10.0.0.0/16"
bastion_instance_type = "t3.micro"
app_instance_type     = "t3.micro"
db_instance_type      = "t3.micro"

key_name           = "sabascia-ex1"
workstation_ip     = "15.248.2.255/32" # da aggiornare per permettere accesso a bastion