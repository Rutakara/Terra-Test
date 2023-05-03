# Creating Kubernetes cluster using Terraform, AWS EC2, Kubeadm 
Kubernetes and DevOps, in general, have a steep learning curve. However, one of the most effective ways to master Kubernetes is through hands-on 
experience. In this work, I will guide you through three essential aspects of the DevOps journey. We will use an IaC  tool to create instances in the cloud, install the Kubernetes cluster, and deploy a static webpage.

Terraform is the most used IaC tool. Terraform and supports all three major cloud providers, namely AWS, GCP, and Azure [1] [2]. For this guide, we create EC2 instances in AWS.

Kubernetes removed Docker runtime support in release 1.22 [6] in late 2021 as Docker is not CRI-compliant. Therefore, we will use CRI-O as our preferred CRI. Additionally, we will use Calico as our CNI. Calico offers superior network performance, flexibility and advanced network administration security capabilities [3].

Requirements:

1. 4 GB memory and 2 CPU for Kubernetes master node. 
2. 1 GB memory and 1 CPU for Kubernetes worker node.  
3. 3 aws EC2 instances. A master node and 2 worker nodes. 
4. Virtual firewalls to allow specific inbound traffic. For these, 2 aws security groups will be configured to manage inbound traffic for both
   master and worker nodes. The following are the ports needed:

Master node:   
Kubernetes master node hosts control plane components. These are apiserver, controller manager, scheduler, etcd, kube-proxy and kubelet. In addition, I will use Calico as CNI. As a result, the following ports need to be opened:
1. TCP 6443      → For Kubernetes API server
2. TCP 2379–2380 → For etcd server client API
3. TCP 10250     → For Kubelet API
4. TCP 10259     → For kube-scheduler
5. TCP 10257     → For kube-controller-manager
6. TCP 22        → For remote access with ssh
7. custom protocol with type All-All for Calico 
Create a security group in aws: Go to EC2 > Network & Security > Create seurity group. Select In-bound traffic, and configure the ports accordingly.   

Worker node:   
Kubernetes worker node hosts kube-proxy and kubelet and therefore, their ports need to be opened. Ports within 30000 to 32767 range need to be opened in order for applications to be accessible through a nodeport service:
1. TCP 10250       → For Kubelet API
2. TCP 30000–32767 → NodePort Services
3. TCP 22          → For remote access with ssh
4. custom protocol with type All-All for Calico
Create a security group in aws: Go to EC2 > Network & Security > Create seurity group. Select In-bound traffic, and configure the ports accordingly.      
## Terraform 
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
  
Create the variable.tf file in Terraform and within your project folder. Refer to the variable in pervious section like this:

        variable "vm_config" {
          description = "List instance objects"
          default = [{}]
        }
        
   
Create main.tf file in Terraform and within your project folder. Paste the following:
 
         provider "aws" {
          region = "us-east-1"
          shared_credentials_file = "<path-your-secret-key>"
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
          key_name = "<name-of-your-secret-key>"
          subnet_id = each.value.subnet_id
          tags = {
            Name = "${each.value.instance_name}"
          }
        }

        output "instances" {
          value       = "${aws_instance.kubeadm}"
          description = "All Machine details"
        }

 
For detailed information about each block in the above code please refer to [5]. Once the above is done, can initialize terraform by the command:

        terraform init
        
Followed by

        terraform plan -var-file=<.tfvars file name> -out <name of output file e.g. terraplan.out>  
        
Apply the plan by running 

        terraform plan <name of output file e.g. terraplan.out> 
        
At this point the instances will initialize and will change to running state soon after. In AWS, search for EC2, then select instances. Select master instance > connect > connect to instance > connect. THis will enable you to login directly to the instance. Repeat the same for the other instances.

## Kubeadm 
Before installing KUbeadm, Kubectl and Kubelet, first we have to perform network setting in all 3 nodes to allow iptables to see bridged traffic. And secondly, we need to install CRI-O. 

         cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
         overlay
         br_netfilter
         EOF

         sudo modprobe overlay
         sudo modprobe br_netfilter

         # sysctl params required by setup, params persist across reboots
         cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
         net.bridge.bridge-nf-call-iptables  = 1
         net.bridge.bridge-nf-call-ip6tables = 1
         net.ipv4.ip_forward                 = 1
         EOF

         # Apply sysctl params without reboot
         sudo sysctl --system
         
Now install CRI-O in all 3 nodes. First enable cri-o repositories by

         cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
         overlay
         br_netfilter
         EOF

Set up required sysctl params in all 3 nodes:

         cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
         net.bridge.bridge-nf-call-iptables  = 1
         net.ipv4.ip_forward                 = 1
         net.bridge.bridge-nf-call-ip6tables = 1
         EOF
         
         sudo modprobe overlay
         sudo modprobe br_netfilter
         
         sudo sysctl --system
         
Enable cri-o repositories:         
              

         OS="xUbuntu_20.04"

         VERSION="1.23"

         cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
         deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /
         EOF
         cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list
         deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /
         EOF


Add gpg keys

         curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/Release.key | sudo apt-key --keyring              /etc/apt/trusted.gpg.d/libcontainers.gpg add -
         curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -
         

install cri-o

         sudo apt-get update
         sudo apt-get install cri-o cri-o-runc cri-tools -y

         sudo systemctl daemon-reload
         sudo systemctl enable crio
         
Now, install kubeadm, kubelet and kubectl in all 3 nodes

         sudo apt-get update
         sudo apt-get install -y apt-transport-https ca-certificates curl

         curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
         echo “deb https://apt.kubernetes.io/ kubernetes-xenial main” | sudo tee -a /etc/apt/sources.list.d/kubernetes.list

         sudo apt-get update -y
         sudo apt-get install -y kubelet kubeadm kubectl    
         
 Make sure container runtime is running, then initialize Kubeadm in master node by,
 
         sudo kubeadm init --apiserver-advertise-address=<master's private IP> --pod-network-cidr=10.244.0.0/16 # Use your master node’s private IP
         
 You will get an output like the following:
 
         kubeadm join 172.31.25.133:6443 --token y2ywn7.ve672iddvw4tn6g4 \
        --discovery-token-ca-cert-hash sha256:f3c89c0b25ba219db3c098686b087a82881d23376787d2324ee9f0b0def02df4
        
 Take not of the token as it will be used later on. 
 
 Now, setup kubeconfig as follows:
 
          mkdir -p $HOME/.kube
          sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
          sudo chown $(id -u):$(id -g) $HOME/.kube/config
         
At this stage, you should be able to list pods in the master node in kube-systen namespace

          kubectl get pods -n kube-system
          
Install Calico network plugin

          kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml

Now when you list your pods once more, you should see Calico pods on the list. It might take a while for the Calico pods to be in a running state.

            ubuntu@master:~$ kubectl get po -n kube-system 
            NAME                                       READY   STATUS    RESTARTS   AGE
            calico-kube-controllers-6c99c8747f-9fwcq   1/1     Running   0          3m34s
            calico-node-79smv                          1/1     Running   0          3m34s
            coredns-5d78c9869d-fk6z6                   1/1     Running   0          14m
            coredns-5d78c9869d-zjxrn                   1/1     Running   0          14m
            etcd-master                                1/1     Running   0          14m
            kube-apiserver-master                      1/1     Running   0          14m
            kube-controller-manager-master             1/1     Running   0          14m
            kube-proxy-c6967                           1/1     Running   0          14m
            kube-scheduler-master                      1/1     Running   0          14m

Go to worker nodes, make sure container runtime is running 

            sudo systemctl daemon-reload
            sudo systemctl enable crio --now
            
Now join each worker node by our previous obtained command

            sudo kubeadm join 172.31.25.133:6443 --token y2ywn7.ve672iddvw4tn6g4 \
            --discovery-token-ca-cert-hash sha256:f3c89c0b25ba219db3c098686b087a82881d23376787d2324ee9f0b0def02df4
            
Now we should be able to list all our nodes. In master node run

            ubuntu@master:~$ kubectl get nodes
            NAME       STATUS   ROLES           AGE     VERSION
            master     Ready    control-plane   25m     v1.27.1
            worker-1   Ready    <none>          2m57s   v1.27.1
            worker-2   Ready    <none>          4m52s   v1.27.1
            
            
Now we can deploy nginx webserver in our cluster and expose it through a nopeport service

            kubectl create deployment test-deployment --image nginx:latest --replicas 3
            kubectl expose deployment test-deployment --port 80 --type NodePort
            
Let's check which port is selected for our nodeport service

            ubuntu@master:~$ kubectl get svc test-deployment
            NAME              TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
            test-deployment   NodePort    10.97.47.79   <none>        80:30101/TCP   12s

Ok. The port is 30101

We can confirm from a web browser using master node IP address and the above port

![image](https://user-images.githubusercontent.com/28569383/235932775-73f02513-0d28-4adb-b7de-492e3c884bfa.png)


Voila! All good...
 
          

            
            
            
            

[1] https://techcommunity.microsoft.com/t5/itops-talk-blog/infrastructure-as-code-iac-comparing-the-tools/ba-p/3205045   
[2] https://bluelight.co/blog/best-infrastructure-as-code-tools   
[3] https://kubevious.io/blog/post/comparing-kubernetes-container-network-interface-cni-providers   
[4] https://github.com/projectcalico/calico/issues/2561   
[5] https://www.middlewareinventory.com/blog/terraform-create-multiple-ec2-different-config/   
[6] https://kubernetes.io/blog/2020/12/02/dont-panic-kubernetes-and-docker/   

         
         


         
         
         
         

        
        
        

     
 
