vm_config = [
  {
    "node_name" : "Master",
    "ami" : "ami-0aa2b7722dc1b5612",
    "no_of_instances" : "1",
    "instance_type" : "t2.medium",
    "subnet_id" : "subnet-780bde35",
    "vpc_security_group_ids" : ["sg-053564b3ef25f1f05"]
  },
  {
    "node_name" : "Worker",
    "ami" : "ami-0aa2b7722dc1b5612",
    "instance_type" : "t2.micro",
    "no_of_instances" : "2"
    "subnet_id" : "subnet-780bde35"
    "vpc_security_group_ids" : ["sg-0e037e6dd7973a887"]
  }
 ]
 