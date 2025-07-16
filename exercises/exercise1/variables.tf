variable "region" {
  type = string
}

variable "instance_type" {
  type = string
}
variable "key_name" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

variable "workstation_ip" {
  type = string
}

variable "amis" {
  type = map(any)
  default = {
    "eu-central-1" : "ami-01424ec0ad897d99b"
    "eu-central-1" : "ami-01424ec0ad897d99b"
  }
}
