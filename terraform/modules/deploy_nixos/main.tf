locals {
  module_files = abspath("${path.module}/../../nixos/")
}

variable "ip" {
  type        = string
  description = "IP of the target host"
}

variable "configuration" {
  type        = string
  description = "Path from nixos module files"
}

variable "id" {
  type        = string
  description = "Instance ID of the target host"
}

variable "hostname" {
  type        = string
  default     = ""
  description = "Hostname of the target host"
}

variable "deployment_name" {
  type        = string
  description = "Name of the nixos deployment, eg: testing"
}

variable "tags" {
  type        = list(string)
  description = "List of tags applied to the host for colmena targeting"
  default     = []
}

variable "keys" {
  type        = map(any)
  description = "List of values passed to the host's configuration function"
  default     = {}
}

variable "private_ip" {
  type    = string
  default = ""
}

variable "public_ip" {
  type    = string
  default = ""
}

variable "availability_zone" {
  type    = string
  default = ""
}

variable "region" {
  type    = string
  default = ""
}

data "aws_instance" "instance" {
  instance_id = var.id
}

data "aws_availability_zone" "zone" {
  name = var.availability_zone == "" ? data.aws_instance.instance.availability_zone : var.availability_zone
}

output "deploy_nixos" {
  value = {
    _type = "nixos_host"

    configuration     = "hosts/${var.configuration}.nix"
    id                = var.id
    ip                = var.ip == "" ? data.aws_instance.instance.private_ip : var.ip
    private_ip        = var.private_ip == "" ? data.aws_instance.instance.private_ip : var.private_ip
    public_ip         = var.public_ip == "" ? data.aws_instance.instance.public_ip : var.public_ip
    hostname          = var.hostname == "" ? data.aws_instance.instance.instance_tags.Name : var.hostname
    deployment_name   = var.deployment_name
    tags              = var.tags
    keys              = var.keys
    region            = var.region == "" ? data.aws_availability_zone.zone.group_name : var.region
    availability_zone = var.availability_zone == "" ? data.aws_instance.instance.availability_zone : var.availability_zone
  }
}
