#!/bin/bash
IFS=$'\n'
dir=$(dirname "$(readlink -f "$0")")
cmd=$1
domain=$2
ing_upt=$3
run_terra() {
	cd $dir/selenium-cluster
	terraform init
	terraform apply -auto-approve
	cd $dir
}
install_aws() {
	aws_path=$(which aws)
	if [ -f "$aws_path" ]; then
		echo "AWS CLI already installed"
	else
		apt-get update -y
		apt install zip unzip git wget -y
		curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$dir/awscliv2.zip"
		unzip awscliv2.zip
		$dir/aws/install
		rm -rfv $dir/aws $dir/awscliv2.zip
	fi
}
conf_aws() {
	aws configure
}

conf_kube() {
	cd $dir/selenium-cluster
	aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name)
	cd $dir
}
destroy_eks(){
	cd $dir/selenium-cluster
	helm uninstall ingress-nginx --namespace ingress-nginx
	helm uninstall selenium-grid --namespace selenium
	kubectl delete ns ingress-nginx
	kubectl delete ns selenium
	nme=$(kubectl get ns selenium --ignore-not-found=true | grep -i active | wc -l)
	inge=$(kubectl get ns ingress-nginx --ignore-not-found=true | grep -i active | wc -l)
	if [ "$nme" -lt 1 ] && [ "$inge" -lt 1 ]; then
		terraform destroy
	else
		echo "Issues Deleting prerequisite resources, Exiting"
		exit 6
	fi
	cd $dir
}
install_kube() {
	kube_path=$(which kubectl)
	if [ -f "$kube_path" ]; then
		echo "Kubectl Already installed in $kube_path"
	else
		apt-get install -y ca-certificates curl
		apt-get install -y apt-transport-https
		curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
		echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
		apt-get update
		apt-get install -y kubectl
	fi
}
install_helm() {
	helm_path=$(which helm)
	if [ -f "$helm_path" ]; then
		echo "Helm CLI is already installed"
	else
		curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
		apt-get install apt-transport-https --yes
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
		apt-get update
		apt-get install helm
	fi
}
install_nginx() {
	exist=$(kubectl get ns ingress-nginx --ignore-not-found=true | grep -i active | wc -l)
	if [ "$exist" -ge 1 ]; then
                echo "Nginx Ingress Controller already exists"
        else
		kubectl create namespace ingress-nginx
		helm repo add nginx-stable https://helm.nginx.com/stable
		helm repo update
		helm install ingress-nginx nginx-stable/nginx-ingress --namespace ingress-nginx
	fi
}
install_sele() {
	nm=$(kubectl get ns selenium --ignore-not-found=true | grep -i active | wc -l)
	if [ "$nm" -ge 1 ]; then
		echo "Selinum already exists"
	else
		kubectl create namespace selenium
		helm repo add docker-selenium https://www.selenium.dev/docker-selenium
		helm repo update
		helm install selenium-grid docker-selenium/selenium-grid --namespace selenium
	fi
}
update_sele_ing() {
	kubectl get ing selenium-ingress -n selenium -o yaml > $dir/ingress.yaml
	#sed -i '#"annotations:"#a "  kubernetes.io/ingress.class: nginx"' $dir/ingress.yaml
	sed -i '5i \    kubernetes.io/ingress.class: nginx' $dir/ingress.yaml
	sed -i "s#selenium-grid.local#$domain#g" $dir/ingress.yaml
	kubectl apply -f $dir/ingress.yaml
	rm -fv $dir/ingress.yaml
}
tester() {
	echo $dir
	tes=$(which zzss)
	if [ -f "$tes" ]; then
		echo "Installed"
	else
		echo "not installed"
	fi

}

if [ $# -lt 1 ]; then
	echo "Too few arguments. use $0 <init/destroy> <custom_domain> <update ingress with domain(y/n)> or $0 destroy"
	echo "Example $0 init test.mydomain.com y"
	echo "If the step is already done in a previous run, then use Example $0 init test.mydomain.com n"
	exit 3
else
	if [ "$cmd" == "init" ]; then
		if [ $# -lt 3 ]; then
			echo "Too few arguments. use $0 <init> <custom_domain> <update ingress with domain(y/n)> "
			exit 4
		else
			install_aws
			conf_aws
			run_terra
			install_kube
			conf_kube
			install_helm
			install_nginx
			install_sele
			if [ "$ing_upt" == "y" ]; then
				update_sele_ing
			else
				echo "Updating Domain in ingress obect skipped"
			fi
		fi
	elif [ "$cmd" == "destroy" ]; then
		destroy_eks
	else
		echo "Unknown Command"
		exit 5
	fi
fi
