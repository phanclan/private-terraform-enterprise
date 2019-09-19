# Automated Installation of PTFE with External Services in AWS  
  
## Source  
  
* [github.com/hashicorp/private-terraform-enterprise/tree/automated-aws-pes-installation][1]  
  
## Overview  
  
* This branch contains Terraform configurations that can do [<u>automated installations][2]</u> of [<u>Private Terraform Enterprise][3]</u> (PTFE) in AWS using either Ubuntu, RHEL, or CentOS.  
    * Supports both **online** or **airgapped** installation methods for all three operating systems.  
    * It supports **private** and **public** networks.  
  
## **Explanation of the Two Stage Deployment Model**  
  
* We deploy the AWS infrastructure and PTFE in two stages using the open source flavor of Terraform.  
    * **Stage 1**:  
        * First, we deploy **network** and **security group** resources that the EC2 instances that run PTFE will run in  
        * Deploy a private **S3 bucket** to upload the PTFE software, license, and settings files  
        * Deploy a **KMS key** to encrypt the S3 bucket.  
        * If deploying a private-network, then deploy an EC2 instance as a **bastion host**.  
        * **NOTE**: We provide two sets of Terraform code for Stage 1. One that provisions a public network and one that provisions a private network.  
    * **Stage 2**:  
        * Then, we deploy the external PostgreSQL database and S3 bucket used in the [<u>Production - External Services][4]</u> operational mode of PTFE  
        * Deploy the **primary** and **optional secondary EC2 instances** that will run PTFE,  
        * Deploy an **Application Load Balancer** and associated resources  
        * Deploy some required IAM resources.  
* NOTE: We are creating an S3 bucket in each of the stages  
    * The bucket created in Stage 1 is the "**PTFE source bucket**"  
    * The bucket created in stage 2 is the "**PTFE runtime bucket**".  
* There are two reasons for splitting the deployment into two stages:  
    * **Main reason**: Some users are not allowed to provision their own VPC, subnets, and security groups.  
        * Splitting the deployment allows those users who are allowed to provision all required AWS resources to first deploy the network and security group resources and the PTFE source bucket from the [<u>network][5]</u> directory, copy the IDs of the VPC, subnets, and security groups into a **terraform.tfvars** file in the [<u>aws][6]</u> directory, and then deploy the rest of the resources.  
    * **Second reason**: Some users want to be able to "repave" their PTFE instances periodically, meaning that they will destroy the instances and recreate them (possibly with a new AMI).  
        * These users need to create the PTFE source bucket and then place the PTFE software and license file in it before they run the Terraform code in stage 2.  
  
## **Description of the User Data Script that Installs PTFE**  
  
* During stage 2, a user data script generated from one of six templates ([<u>user-data-ubuntu-online.tpl][7]</u>, [<u>user-data-ubuntu-airgapped.tpl][8]</u>. [<u>user-data-rhel-online.tpl][9]</u>, [<u>user-data-rhel-airgapped.tpl][10]</u>, [<u>user-data-centos-online.tpl][11]</u>, or [<u>user-data-centos-airgapped.tpl][12]</u>) is run on each instance to install PTFE on it and to initialize the PostgreSQL database and S3 bucket if that has not already been done.  
    * The online scripts also install Docker.  
    * Since the user data script is templated, all relevant PTFE settings, whether entered in the **terraform.tfvars** file or computed by Terraform, are passed into it before it is run when the instances are deployed.  
* The script does the following things:  
    * It determines the private IP, private DNS, and public IP (in public networks) of each EC2 instance being deployed to run PTFE.  
    * It writes out the **replicated.conf**, **ptfe-settings.json**, and **create_schemas.sql** files.  
* At this point, different things happen depending on whether an "**online**" or "**airgapped**" installation is being done.  
* In an an [<u>online][13]</u> installation, the script does the following:  
    * Installs the AWS CLI and uses it to retrieve the PTFE license file from the PTFE source bucket.  
    * Sets SELinux to permissive mode (except on RHEL).  
    * Installs the `psql` utility and connects to the PostgreSQL database in order to create the three schemas needed by PTFE.  
    * Downloads the PTFE installer using curl and then runs it to install both Docker and PTFE.  
* In an [<u>airgapped][14]</u> installation, we use AMIs that already have the aws CLI, psql, and Docker pre-installed. So, the script only does the following:  
    * Downloads the PTFE license, airgap bundle, and the replicated bootstrapper (replicated.tar.gz) from the PTFE source bucket.  
    * Runs the installer in airgapped mode to install PTFE.  
* In either case, the installer uses the **replicated.conf**, **ptfe-settings.json**, **create_schemas.sql**, and **ptfe-license.rli** files that the script previously wrote to disk.  
* The script then enters a loop, testing the availability of the PTFE app with a curl command until it is ready.  
* Finally, the script uses the TFE API to create  
    * the first site admin user,  
    * a TFE API token for this user, and  
    * the first organization.  
    * This leverages the [<u>Initial Admin Creation Token][15]</u> (IACT).  
    * At this point, the generated API token could be used to automate additional PTFE configuration if desired.  
  
## **Example tfvars Files**  
  
* There are five example tfvars files that you can use with the Terraform configurations in this branch:  
    * [<u>public network.auto.tfvars.example][16]</u> for use in stage 1 when deploying a public network.  
    * [<u>private network.auto.tfvars.example][17]</u> for use in stage 1 when deploying a private network.  
    * [<u>ubuntu.auto.tfvars.example][18]</u> for use in Stage 2 when deploying to Ubuntu.  
    * [<u>rhel.auto.tfvars.example][19]</u> for use in Stage 2 when deploying to RHEL.  
    * [<u>centos.auto.tfvars.example][20]</u> for use in Stage 2 when deploying to CentOS.  
* These files assume you are provisioning to the **us-east-1** region.  
    * If you change this, make sure you select AMI IDs that exist in your region.  
    * We have built Ubuntu, RHEL, and CentOS AMIs that have Docker, the aws CLI, and the psql client pre-installed; these are suitable for use with the airgapped installation option.  
    * However, while we were able to make the Ubuntu and RHEL AMIs public, we were not able to make the CentOS AMI public.  
    * See the tfvars files for the AMI IDs.  
* Be sure to adjust the following variables if deploying for a POC or in production.  
    * aws_instance_type,  
    * database_storage,  
    * database_instance_class  
    * database_multi_az  
    * Also set **create_second_instance** to "**1**" if you want to provision a secondary PTFE instance in case the first one fails.  
* The last three files (ubuntu, rhel, and centos) can be used with both online and airgapped installations.  
    * If doing an **online** installation, set **operational_mode** to "**online**".  
    * If doing an **airgapped** installation, set **operational_mode** to "**airgapped**".  
* After doing an initial deployment, you should change **create_first_user_and_org** to "**false**" since the initial site admin user can only be created once.  
  
## **Prerequisites**  
  
* You need to have an AWS account before running the first stage Terraform code in either the [<u>network-public][21]</u> or the [<u>network-private][22]</u> directory of this repository.  
* You need to have the following things before running the stage 2 Terraform code in the [<u>aws][23]</u> directory of this repository:  
    * an AWS account  
    * a VPC like the one provisioned in stage 1  
    * at least two subnets in that VPC like the ones provisioned in stage 1 (You can just use the same subnets for the EC2 instances, the PostgreSQL database, and the ALB or use separate subnets for these.) If you have more than two subnets, make sure that the two specified in the **alb_subnet_ids** variable include those containing the EC2 instances running PTFE.  
    * a security group like the one provisioned in stage 1  
    * an S3 bucket like the one provisioned in stage 1 (to be used as the PTFE source bucket)  
    * an AWS KMS key like the one provisioned in stage 1  
    * An AWS AMI running a Ubuntu, RHEL, or CentOS in the region in which you plan to deploy PTFE  
    * An AWS key pair that can be used to SSH to the EC2 instances that will be provisioned to run PTFE.  
    * An existing AWS Route 53 zone to host the Route 53 record set that will be provisioned.  
        * This needs to be a public zone so that the ACM cert created can be validated against a record set created in that zone.  
        * If you absolutely need to use a private zone, provide your own ACM cert and remove the code that provisions the additional ACM cert.  
    * Access to a PTFE license  
    * Access to a PTFE airgap bundle and **replicated.tar.gz** installer bootstrapper that you can upload to the PTFE source bucket (if doing an airgapped installation).  
    * Access to Docker and packages it requires so that you can upload them to the PTFE source bucket (if doing an airgapped installation).  
* You can also provide the ARN of a certificate that you uploaded into or created within Amazon Certificate Manager (ACM).  
    * This will be attached to the listeners created for the application load balancer that will be provisioned in front of the EC2 instances.  
    * The stage 2 Terraform code actually creates an ACM certificate whether you provide one or not, but if you do provide your own, the generated one is associated with a fake domain consisting of "fake-" concatenated to your hostname.  
    * If you set the **ssl_certificate_arn** variable to "", the generated ACM cert will be associated with your hostname.  
    * We generate an ACM cert even if you provide your own in order to make the generation of an ACM cert optional in Terraform 0.11. (This will not be needed with Terraform 0.12.)  
  
## **Installing PTFE**  
  
* Please follow these steps to deploy PTFE in your AWS account.  
* **Clone the Repository and Switch to Right Branch**  
    * 1.	On your local computer, navigate to a directory such as **GitHub/hashicorp** into which you want to clone this repository. The code in the next step will create a `private-terraform-enterprise` directory under whichever directory you start in.  
    * 2.	Clone the repository.  
        * `git clone https://github.com/hashicorp/private-terraform-enterprise.git`  
    * 3.	Navigate into the cloned repository.  
        * `cd private-terraform-enterprise`  
    * 4.	Switch to the **automated-aws-pes-installation** branch.  
        * `git checkout automated-aws-pes-installation`  
* **Provision Stage 1**  
    * If you want to use the Terraform code in either the `examples/aws/network-public` or the `examples/aws/network-private` directory to create the VPC, subnets, other network resources, security group, KMS key, and PTFE source bucket, then follow these steps.  
        * Otherwise, create the equivalent resources using some other method and then skip to Stage 2.  
    * 1.	Run `cd examples/aws/network-public` or `cd examples/aws/network-private` to navigate to one of the network directories that contains the Stage 1 Terraform code.  
    * 2.	Create your own tfvars file.  
        * `cp network.auto.tfvars.example network.auto.tfvars`  
    * 3.	Edit **network.auto.tfvars**.  
        * Set **namespace** to "`<name>-ptfe`" where "`<name>`" is some suitable prefix for your PTFE deployment,  
            * ` namespace = "pphan-ptfe" `  
        * Set region  
            * `aws_region = "us-west-2"`  
        * Set **bucket_name** to the name of the PTFE source bucket you wish to create,  
            * ` bucket_name = "pphan-ptfe-source-bucket" `  
        * Set **cidr_block** to a valid CIDR block, and  
            * `cidr_block = "10.110.0.0/16"`  
        * Set **subnet_count** to the number of subnets you want in your VPC.  
            * `subnet_count = "2"`  
        * NOTE  
            * When creating a **public** network, all of the subnets will be public.  
            * When creating a **private** network, that number of private subnets will be created along with one public subnet to allow outbound internet access.  
            * If creating a private network, also set **ssh_key_name** in `<linux>.auto.tfvars` file to the name of your SSH key pair so it can be used with the bastion host created in the private network.  
        * Save the file.  
    * Set Environment Variables  
        * 4.	Export **AWS_ACCESS_KEY_ID**.  
            * `export AWS_ACCESS_KEY_ID=<your_aws_key>`  
        * 5.	Export **AWS_SECRET_ACCESS_KEY.**  
            * `export AWS_SECRET_ACCESS_KEY=<your_aws_secret_key>`  
        * 6.	Export **AWS_DEFAULT_REGION**. us-east-1 or pick some other region.  
            * `export AWS_DEFAULT_REGION=us-east-1`  
            * If you select a different region, make sure you select AMIs from that region.  
    * 7.	Initialize the Stage 1 Terraform configuration and download providers.  
        * `terraform init`  
    * 8.	Provision the Stage 1 resources.  
        * `terraform apply -auto-approve`  
        * Type "**yes**" if prompted. The apply takes about 1 minute.  
    * 9.	Note the following outputs, which you will need in Stage 2.  
        * kms_id  
        * security_group_id  
        * subnet_ids  
        * vpc_id  
        * NOTE: When creating a **private network**, you will have **private_subnet_ids** and **public_subnet_id** outputs instead of the **subnet_ids** output.  
        * Output  
            * ```  
                Apply complete! Resources: 11 added, 0 changed, 0 destroyed.  
                  
                Outputs:  
                  
                kms_id = dd426811-fefe-4dc7-a066-a5831c491fea  
                security_group_id = sg-044d2fa528be7fab3  
                subnet_ids = [  
                    subnet-004104bd18adc76de,  
                    subnet-0cf7aad3e3d1ba7e4  
                ]  
                vpc_id = vpc-0736a6232e22e59a9  
  
    * 10.	Run `cd ..` to go back to the `examples/aws` directory.  
        * `cd ..`  
    * 11.	Add your PTFE license file to your PTFE source bucket that was created.  
        * You can do this in the AWS Console.  
        * If doing an airgapped installation, add your airgap bundle and replicated.tar.gz to the PTFE source bucket too.  
        * Name the various objects in your PTFE source bucket to match the values given in the your tfvars file, taking into account the version of your airgap bundle.  
        * Avoid the use of spaces in the names of the PTFE license and installation files.  
* **Provision Stage 2**  
    * Follow these steps to provision the Stage 2 resources.  
    * 1.	Make sure you are in the `examples/aws` directory of the cloned repository.  
    * 2.	If you skipped Stage 1, do steps 4-6 of that stage to export your AWS keys and default region.  
    * 3.	Copy one of the `tfvars.example` files to a file with the same name but without the "**example**" extension.  
        * `cp ubuntu.auto.tfvars.example ubuntu.auto.tfvars`  
    * 4.	Edit the "**<linux_flavor>.auto.tfvars**" file where **<linux_flavor>** is the flavor of Linux you are using.  
        * Set **namespace** to the same namespace you set in Stage 1.  
            * ` namespace = "pphan-ptfe" `  
        * Set **source_bucket_name** to the value of **bucket_name** you set in **network.auto.tfvars**.  
            * ` source_bucket_name = "pphan-ptfe-source-bucket"`  
            * This references the bucket with the source files.  
        * Set **vpc_id, ptfe_subnet_ids, db_subnet_ids, alb_subnet_ids**, and **security_group_id** to the corresponding outputs from Stage 1 or the IDs of the resources you created using other means.  
            * **NOTE**: The `*_subnet_ids` should be in the form `"<subnet_1>,<subnet_2>"` with no space after the comma.  
            * The **ptfe** and **db** subnets can be distinct or the same and can be public or private.  
            * The **alb** subnets must be public.  
        * Set **s3_sse_kms_key_id** to the **kms_id** output from Stage 1 or the ID of the KMS key you created using other means.  
            * Example  
                * ` 3740ade7-649c-4a3e-8f0e-7b524dd65db5`  
        * Set **public_ip** to  
            * "**true**" if you want the EC2 instances to have public IPs (pp)  
            * "**false**" if you don't want the EC2 instances to have public IPs.  
        * Set **alb_internal** to  
            * "**false**" if you want the ALB to not be internal (pp)  
            * "**true**" if you want the ALB to be internal  
    * 5.	Set the rest of the variables in the "**<linux_flavor>.auto.tfvars**" file.  
        * Set **aws_instance_type** to  
            * "**m5.large**" for demos and POCs  
            * "m5.large", "**m5.xlarge**" or "**m5.2xlarge**" for production  
        * Set **database_storage** to  
            * "**10**" for demos (default)  
            * "**20**" for POCs  
            * "**50**" for production.  
        * Set **database_instance_class** to  
            * "**db.t2.medium**" for demos (default)  
            * "**db.m4.large**" for POCs  
            * "**db.m4.large**", "**db.m4.xlarge**" or "**db.m4.2xlarge**" for production.  
        * Set **database_multi_az** to  
            * "**false**" for demos (default)  
            * "**true**" for POCs and production.  
        * Set **create_second_instance** to  
            * "**1**" if you want a second PTFE instance.  
            * Otherwise, leave it set to "**0**".  
        * Set **ssh-keyname** to the name of your SSH keypair as it is displayed in the AWS Console.  
            * I added a resource to create a ssh_key_pair  
                * ```  
                    resource "aws_key_pair" "ec2_key" {  
                      key_name   = "${var.namespace}-ec2-key"  
                      public_key = "<key>"  
                    }  
  
            * ` ssh_key_name = "pphan-ptfe-ec2-key"`  
        * Set **ssl_certificate_arn** to the full ARN of the certificate you uploaded into or created within **Amazon Certificate Manager (ACM)**,  
            * but if you want to use the ACM cert that Terraform will generate, set this to "" (blank).  
        * `owner` and `ttl` are used within HashiCorp's own AWS account for resource reaping purposes. You can leave these blank if you do not work at HashiCorp.  
            * `owner = "pphan"`  
            * `ttl = "24h"`  
        * Set **ptfe_license** to the name of the object in your PTFE source bucket that contains your PTFE license.  
            * `hashicorp-internal---se.rli`  
        * Set the four password fields with suitable passwords.  
        * Set **operational_mode** to  
            * "**online**" (pp)  
            * "**airgapped**"  
        * See [<u>PTFE Automated Installation][24]</u> for guidance on the various PTFE settings that are passed into the **replicated.conf** and **ptfe-settings.json** files in the *.tpl files.  
            * In particular, be sure to provide non-blank values for  
            * hostname,  
            * enc_password,  
            * pg_dbname,  
            * pg_extra_params,  
            * pg_password,  
            * pg_user,  
            * s3_bucket,  
            * **s3_region** (which would generally be the same as aws_region),  
            * **s3_sse_kms_key_id**, and  
            * **operational_mode**.  
        * If doing an **airgapped** installation, set the **airgap_bundle**, and **replicated_bootstrapper** variables to the names of the corresponding items that you placed in your PTFE source bucket.  
        * If doing an initial installation, make sure **create_first_user_and_org** is set to "**true**".  
        * Set the **initial_admin_*** properties to desired values.  
    * 6.	Initialize the Stage 2 Terraform configuration and download providers.  
        * `terraform init`  
    * 7.	Provision the Stage 2 resources.  
        * `terraform apply`  
        * Type "**yes**" when prompted.  
        * **NOTE**: The apply takes about **5-10 minutes**. Much of the time is spent creating the PostgreSQL database in RDS.  
        * Output  
            * ```  
                Apply complete! Resources: 19 added, 0 changed, 0 destroyed.  
                  
                Outputs:  
                  
                db_endpoint = pphan-ptfe-db-instance.cflpqd1xguki.us-west-2.rds.amazonaws.com:5432  
                ptfe_fqdn = pphan-ptfe.hashidemos.io  
                ptfe_private_dns = [  
                    ip-10-110-1-73.us-west-2.compute.internal  
                ]  
                ptfe_private_ip = [  
                    10.110.1.73  
                ]  
                ptfe_public_dns = [  
                    ec2-54-184-113-93.us-west-2.compute.amazonaws.com  
                ]  
                ptfe_public_ip = [  
                    54.184.113.93  
                ]  
  
    * SSH to EC2 instance  
        * 8.	After you see outputs for the apply, go to the **AWS Console > EC2**, and find your "`<namespace>-instance-1`" instance.  
        * 9.	Click the **Connect** button and copy the SSH connection command.  
        * 10.	Type that command in a shell that contains your SSH private key from your AWS key pair and connect to your primary PTFE instance. (It might not be ready right away.)  
            * `ssh -i <key> [ubuntu | ec2-user]@<public_ip>`  
    * 11.	Now, **tail** the **install-ptfe.log**.  
        * `tail -f install-ptfe.log`  
        * NOTE: It is ok if you see multiple warnings in the log like "`curl: (6) Could not resolve host: <ptfe_dns>`".  
        * This just means that the script has run the installer and is currently testing the availability of the PTFE application with curl every 15 seconds.  
        * If this lasts for more than 5 minutes, then something is wrong.  
        * When the **install-ptfe.log** stops showing curl calls against the hostname and instead shows output related to the creation of the initial admin user and organization, then things should be good.  
        * Quick checks  
            * Connect with psql  
                * `psql -h <db_endpoint> -d ptfe -U <pg_user>`  
                * Output  
                    * ```  
                        ptfe-> \dn  
                           List of schemas  
                           Name   |  Owner  
                        ----------+----------  
                         public   | postgres  
                         rails    | postgres  
                         registry | postgres  
                         vault    | postgres  
                        (4 rows)  
  
    * 12.	Point a browser tab against `https://<ptfe_dns>`.  
        * `https://pphan-ptfe.hashidemos.io:8800`  
    * Change your EC2 Security Group.  
        * Restrict access to 22, 8800 to only your IP.  
        * Consider the same for 80 and 443.  
    * 13.	Enter your username and your password and start using your new PTFE server.  
    * If you get any errors during the Stage 2 apply related to the creation of the EC2 instances or the ALB, you can try running `terraform apply` a second time.  
        * If the second apply is successful, then the user-data script on the primary EC2 instance should be able to get out of the curl loop and create the initial site admin user and organization.  
    * **NOTE: You do not need to visit the PTFE admin console at port 8800 when deploying PTFE with the process given on this branch of this repository.**  
* Destroy  
    * `terraform destroy`  
    * NOTE: Takes about 10 minutes  
* Changes  
    * I added a resource to create a ssh_key_pair  
        * ```  
            resource "aws_key_pair" "ec2_key" {  
              key_name   = "${var.namespace}-ec2-key"  
              public_key = "<key>"  
            }  
            ```  
  
    * Added the following to module database/main.tf aws_db_instance.ptfe  
        * ```  
            changes  
              skip_final_snapshot       = "true"  
              backup_retention_period   = "0" # disable backup  
  
* Troubleshooting  
    * You can tail the audit log and watch it as you click around the TFE UI.  Just log into your server and run  
        * `docker logs -f ptfe_atlas | grep “Audit Log”`  
        * `docker logs ptfe_atlas --since 5m | grep “Audit Log”`  
  
## **A Comment About Certs**  
  
* The Terraform code in this branch of this repository uses self-signed certs generated by PTFE on the EC2 instances and an ACM certificate on the listeners associated with the Application Load Balancer that it creates.  
    * As mentioned above, you can provide your own cert or let the Terraform code generate one for you.  
    * If you provide your own cert, it would ideally be a cert signed by a public certificate authority to better support integration with version control systems.  
    * It is possible to use a cert signed by a private certificate authority, but you then need to make sure that your VCS system (if using one of our [<u>supported VCS integrations][25]</u>) trusts that certificate authority.  
  
## **A Comment About Proxies**  
  
* While the code includes the **extra_no_proxy** variable and passes it into the generated **ptfe-settings.json** file through the template (*.tpl) files, it does not currently support proxies at this time since the commands used to run the PTFE installer include the no-proxy flag.  
    * If you need to use a proxy server, you could change those install commands to use http-proxy=<proxy_server>:<port> instead of no-proxy and also add additional-no-proxy=<comma-separated-list> to list the addresses that should bypass the proxy in a comma-delimited list without any spaces.  
    * Also change the default value of extra_no_proxy to include those same addresses.  
  
## **Repaving Your PTFE Instances With Terraform**  
  
* You can replace or "repave" the EC2 instance(s) running PTFE with Terraform at any time by following this process:  
    * 1.	Terminate the EC2 instance(s) in the AWS Console or `taint` them by running  
        * `terraform taint -module=pes aws_instance.primary`  
        * and/or  
        * `terraform taint -module=pes aws_instance.secondary`  
    * 2.	Re-run terraform apply.  
        * `terraform apply`  
        * This will cause the EC2 instance(s) to be destroyed and recreated.  
        * In addition, it will cause the **aws_lb_target_group_attachment** resources associated with the application load balancer to be destroyed and recreated; this ensures that the ALB will always point to the primary PTFE instance.  
* When repaving instances, you should set the **create_first_user_and_org** variable to "**false**" since you will have already created the first site admin user and organization.  
  
[1]: https://github.com/hashicorp/private-terraform-enterprise/tree/automated-aws-pes-installation  
[2]: https://www.terraform.io/docs/enterprise/private/automating-the-installer.html  
[3]: https://www.terraform.io/docs/enterprise/private/index.html  
[4]: https://www.terraform.io/docs/enterprise/private/preflight-installer.html#operational-mode-decision  
[5]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/network  
[6]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws  
[7]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/user-data-ubuntu-online.tpl  
[8]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/user-data-ubuntu-airgapped.tpl  
[9]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/user-data-rhel-online.tpl  
[10]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/user-data-rhel-airgapped.tpl  
[11]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/user-data-centos-online.tpl  
[12]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/user-data-centos-airgapped.tpl  
[13]: https://www.terraform.io/docs/enterprise/private/install-installer.html#run-the-installer-online  
[14]: https://www.terraform.io/docs/enterprise/private/install-installer.html#run-the-installer-airgapped  
[15]: https://www.terraform.io/docs/enterprise/private/automating-initial-user.html  
[16]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/network-public/network.auto.tfvars.example  
[17]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/network-private/network.auto.tfvars.example  
[18]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/ubuntu.auto.tfvars.example  
[19]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/rhel.auto.tfvars.example  
[20]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/centos.auto.tfvars.example  
[21]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/network-public  
[22]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws/network-private  
[23]: https://github.com/hashicorp/private-terraform-enterprise/blob/automated-aws-pes-installation/examples/aws  
[24]: https://www.terraform.io/docs/enterprise/private/automating-the-installer.html  
[25]: https://www.terraform.io/docs/enterprise/vcs/index.html  
