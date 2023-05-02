# Creating Kubernetes cluster using Terraform, AWS EC2, Kubeadm and install 
Kubernetes and DevOps, in general, have a steep learning curve. However, one of the most effective ways to master Kubernetes is through hands-on 
experience. In this document, I will guide you through three essential aspects of the DevOps journey. We will create an Infrastructure as Code (IaC)
 tool to spin up instances in the cloud, install a managed Kubernetes cluster, and deploy a static webpage.

There are numerous choices available when it comes to Infrastructure as Code (IaC) tools. However, most of IaC tools are limited to a specific cloud 
provider. Terraform, on the other hand, is the most widely used tool and supports all three major cloud providers, namely AWS, GCP, and Azure [1] [2].
 For this guide, we will select AWS as our cloud infrastructure provider. We will cover GCP and Azure separately in the future.

To bootstrap Kubernetes, we will use Kubeadm. It's important to note that Kubernetes removed Docker runtime support in release 1.22 [6] in late 2021 as Docker is not 
CRI-compliant. Therefore, we will use CRI-O as our preferred CRI. Additionally, we will use Calico as our CNI. Calico offers superior network 
performance, flexibility and advanced network administration security capabilities [3].
## Creating multi-configuration aws EC2 instances
1. When creating EC2 instances of the same configuration you easily use "count" of "for each". But if you need to create a Kubernetes cluster, a set of master nodes and a set of worker nodes will have different CPU,memory requirements and also, different security group configurations.
2. In this work, I demonstrate how to create sets of Kubernetes master and worker nodes.
3. This approach can be used for multiple master nodes. But for simplicity, let's consider a simple cluster with 1 master, and 2 worker nodes. 
## Master node
Kubernetes master node hosts control plane components. These are apiserver, controller manager, scheduler, etcd, kube-proxy and kubelet. In addition, I will use Calico as CNI. As a result, the following ports need to be opened:
1. TCP 6443      → For Kubernetes API server
2. TCP 2379–2380 → For etcd server client API
3. TCP 10250     → For Kubelet API
4. TCP 10259     → For kube-scheduler
5. TCP 10257     → For kube-controller-manager
6. TCP 22        → For remote access with ssh
7. custom protocol with type All-All for Calico 
Create a security group in aws: Go to EC2 > Network & Security > Create seurity group. Select In-bound traffic, and configure the ports accordingly. 
## Worker node
Kubernetes worker node hosts kube-proxy and kubelet and therefore, their ports need to be opened. Ports within 30000 to 32767 range need to be opened in order for applications to be accessible through a nodeport service:
1. TCP 10250       → For Kubelet API
2. TCP 30000–32767 → NodePort Services
3. TCP 22          → For remote access with ssh
4. custom protocol with type All-All for Calico
Create a security group in aws: Go to EC2 > Network & Security > Create seurity group. Select In-bound traffic, and configure the ports accordingly.      
## Create a .tfvars terraform file
We need to manage our instances as variables. Create a project folder. Open the folder within Terraform. Under this folder, create a .tfvars file. Paste:

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
 
1. "vm_config" is variable name. The variable is an array and it contains our two instances. 
2. "node_name" is the name of our nodes. We are using Master and Worker.
3. "ami" is the amazon machine image. We use Ubuntu ami-0aa2b7722dc1b5612 for this demo.
4. "no_of_instances" is number of instances.
5. "instance_type" is instance type. We select t2.medium (2 CPUs and 4 GB RAM) for master, and t2.micro (1 CPUs and 1 GB RAM).
6. "subnet_id" is subnet id. Here I selected default subnets. You are welcome to create your own vpc/subnets and provide the id as required.
7.  "vpc_security_group_ids" is security groups created in previous sections.
## Create a variable.tf terraform file
Create the variable.tf file in Terraform and within your project folder. Refer to the variable in pervious section like this:

        variable "vm_config" {
          description = "List instance objects"
          default = [{}]
        }
        
   
 ## Create main.tf file in Terraform and within your project folder. Paste the following:
 
         provider "aws" {
          region = "us-east-1"
          shared_credentials_file = "C:/Users/owner/.aws/credentials"
          }

        locals {
          serverconfig = [
            for srv in var.vm_config : [
              for i in range(1, srv.no_of_instances+1) : {
                instance_name = "${srv.node_name}-${i}"
                instance_type = srv.instance_type
                subnet_id   = srv.subnet_id
                ami = srv.ami
                security_groups = srv.vpc_security_group_ids
              }
            ]
          ]
        }

        // We need to Flatten it before using it
        locals {
          instances = flatten(local.serverconfig)
        }

        resource "aws_instance" "kubeadm" {

          for_each = {for server in local.instances: server.instance_name =>  server}

          ami           = each.value.ami
          instance_type = each.value.instance_type
          vpc_security_group_ids = each.value.security_groups
          key_name = "kubeAdmin"
          subnet_id = each.value.subnet_id
          tags = {
            Name = "${each.value.instance_name}"
          }
        }

        output "instances" {
          value       = "${aws_instance.kubeadm}"
          description = "All Machine details"
        }

 
For detailed information about each block in the above code please refer to this link https://www.middlewareinventory.com/blog/terraform-create-multiple-ec2-different-config/ .

Once the above is done, can initialize terraform by the command:

        terraform init
        
Followed by

        terraform plan -var=<.tfvars file name> -out <name of output file e.g. terraplan.out>  
        
Apply the plan by running 

        terraform plan <name of output file e.g. terraplan.out> 
        
At this point the instances will initialize and will change to running state soon after.

## Login to the EC2 instances
        
        
        

     
 