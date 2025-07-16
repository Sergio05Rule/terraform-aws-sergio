availability_zones = ["eu-central-1a", "eu-central-1b"]
instance_type      = "t3.micro" # ARM compatibili con cidr_block         = "10.0.0.0/16"
cidr_block         = "10.0.0.0/16"

key_name           = "sabascia-ex1"
workstation_ip     = "15.248.3.95/32" # da aggiornare per permettere accesso a bastion