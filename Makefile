# Makefile for WordPress on Kubernetes

# Load environment variables from .env file if it exists
# This ensures that variables defined in .env take precedence or provide defaults.
ifeq ($(wildcard ./.env), ./.env)
    include ./.env
    export $(shell sed 's/=.*//' ./.env)
endif

# Variables - these will now be defaults if not set in .env or overridden on the command line
NAMESPACE ?= wordpress
WORDPRESS_RELEASE ?= wordpress-0.1.0 # Semantic versioning for your release
MARIADB_ROOT_PASSWORD ?= changeme_root
MARIADB_DATABASE ?= wordpress
MARIADB_USER ?= wordpress
MARIADB_PASSWORD ?= changeme_wp

INGRESS_HOST ?= wordpress.localhost
MARIADB_IMAGE ?= mariadb:10.11
WORDPRESS_IMAGE ?= wordpress:6.8.1-php8.2-fpm
NGINX_IMAGE ?= nginx:1.24


# Kubernetes YAML files
K8S_YAML_FILES = \
	k8s/namespace.yaml \
	k8s/configmap-nginx.yaml \
	k8s/configmap-wordpress.yaml \
	k8s/mariadb-service.yaml \
	k8s/mariadb-statefulset.yaml \
	k8s/wordpress-pvc.yaml \
	k8s/wordpress-web-deployment.yaml \
	k8s/wordpress-service.yaml \
	k8s/ingress.yaml

.PHONY: all deploy update delete clean help setup-minikube check-prereqs create-secrets check-env-file

all: help

help:
	@echo "WordPress Kubernetes Deployment Makefile"
	@echo "----------------------------------------"
	@echo "Targets:"
	@echo "  deploy               - Deploy the WordPress application to Kubernetes."
	@echo "  update               - Update the WordPress application on Kubernetes (applies changes)."
	@echo "  delete               - Delete the WordPress application from Kubernetes."
	@echo "  clean                - Delete the Kubernetes resources AND associated PVCs (USE WITH CAUTION - DATA LOSS)."
	@echo "  setup-minikube       - Setup Minikube with required add-ons."
	@echo "  check-prereqs        - Check for kubectl, sed, and .env file existence."
	@echo ""
	@echo "Variables (can be overridden via .env or command line):"
	@echo "  NAMESPACE            - Kubernetes namespace (default: $(NAMESPACE))"
	@echo "  WORDPRESS_RELEASE    - Release version (default: $(WORDPRESS_RELEASE))"
	@echo "  MARIADB_ROOT_PASSWORD - MariaDB root password (default: $(MARIADB_ROOT_PASSWORD))"
	@echo "  MARIADB_DATABASE     - MariaDB database name (default: $(MARIADB_DATABASE))"
	@echo "  MARIADB_USER         - MariaDB user (default: $(MARIADB_USER))"
	@echo "  MARIADB_PASSWORD     - MariaDB password (default: $(MARIADB_PASSWORD))"
	@echo "  INGRESS_HOST         - Ingress Host (default: $(INGRESS_HOST))"
	@echo "  MARIADB_IMAGE        - MariaDB Docker image (default: $(MARIADB_IMAGE))"
	@echo "  WORDPRESS_IMAGE      - WordPress FPM Docker image (default: $(WORDPRESS_IMAGE))"
	@echo "  NGINX_IMAGE          - Nginx Docker image (default: $(NGINX_IMAGE))"
	@echo ""
	@echo "Example usage:"
	@echo "  make deploy"
	@echo "  make NAMESPACE=test-wp deploy"
	@echo "  make MARIADB_ROOT_PASSWORD=my_secure_root_pass deploy"

# New target to check and create .env file if it doesn't exist
check-env-file:
	@if [ ! -f ".env" ]; then \
		echo "'.env' file not found. Copying 'default.env' to '.env'..."; \
		cp default.env .env; \
		echo "Please review and update the '.env' file with your specific configurations and secrets."; \
	fi

check-prereqs: check-env-file # Add check-env-file as a dependency
	@echo "Checking prerequisites..."
	@command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl is required but not installed. Aborting."; exit 1; }
	@command -v sed >/dev/null 2>&1 || { echo >&2 "sed is required but not installed. Aborting."; exit 1; }
	@echo "Prerequisites checked successfully."

# Setup Minikube
setup-minikube: check-prereqs
	@echo "Starting Minikube (if not running) and enabling add-ons..."
	minikube start
	minikube addons enable ingress
	@echo "Minikube setup complete."

# Create/Update Kubernetes Secrets
create-secrets:
	@echo "Creating/Updating Kubernetes secrets in namespace: $(NAMESPACE)..."
	@kubectl create secret generic wordpress-secrets \
		--from-literal=mariadb-root-password=$(MARIADB_ROOT_PASSWORD) \
		--from-literal=mariadb-password=$(MARIADB_PASSWORD) \
		--namespace=$(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo "Secrets processed."

# Deploy the application
deploy: check-prereqs create-secrets
	@echo "Deploying WordPress to Kubernetes namespace: $(NAMESPACE)..."
	@for file in $(K8S_YAML_FILES); do \
		sed \
		-e "s|NAMESPACE_PLACEHOLDER|$(NAMESPACE)|g" \
		-e "s|MARIADB_DATABASE_PLACEHOLDER|$(MARIADB_DATABASE)|g" \
		-e "s|MARIADB_USER_PLACEHOLDER|$(MARIADB_USER)|g" \
		-e "s|WORDPRESS_RELEASE_PLACEHOLDER|$(WORDPRESS_RELEASE)|g" \
		-e "s|INGRESS_HOST_PLACEHOLDER|$(INGRESS_HOST)|g" \
		-e "s|MARIADB_IMAGE_PLACEHOLDER|$(MARIADB_IMAGE)|g" \
		-e "s|WORDPRESS_IMAGE_PLACEHOLDER|$(WORDPRESS_IMAGE)|g" \
		-e "s|NGINX_IMAGE_PLACEHOLDER|$(NGINX_IMAGE)|g" \
		$$file | kubectl apply -f -; \
	done
	@echo "Deployment initiated. Use 'kubectl get all -n $(NAMESPACE)' to check status."

# Update the application
update: check-prereqs create-secrets
	@echo "Updating WordPress application in namespace: $(NAMESPACE)..."
	@for file in $(K8S_YAML_FILES); do \
		sed \
		-e "s|NAMESPACE_PLACEHOLDER|$(NAMESPACE)|g" \
		-e "s|MARIADB_DATABASE_PLACEHOLDER|$(MARIADB_DATABASE)|g" \
		-e "s|MARIADB_USER_PLACEHOLDER|$(MARIADB_USER)|g" \
		-e "s|WORDPRESS_RELEASE_PLACEHOLDER|$(WORDPRESS_RELEASE)|g" \
		-e "s|INGRESS_HOST_PLACEHOLDER|$(INGRESS_HOST)|g" \
		-e "s|MARIADB_IMAGE_PLACEHOLDER|$(MARIADB_IMAGE)|g" \
		-e "s|WORDPRESS_IMAGE_PLACEHOLDER|$(WORDPRESS_IMAGE)|g" \
		-e "s|NGINX_IMAGE_PLACEHOLDER|$(NGINX_IMAGE)|g" \
		$$file | kubectl apply -f -; \
	done
	@echo "Update applied. Use 'kubectl rollout status deployment/wordpress-web -n $(NAMESPACE)' to monitor."

# Delete the application (keeps PVCs)
delete: check-prereqs
	@echo "Deleting WordPress application from namespace: $(NAMESPACE) (PVCs will remain)..."
	@for file in $(K8S_YAML_FILES); do \
		sed \
		-e "s|NAMESPACE_PLACEHOLDER|$(NAMESPACE)|g" \
		-e "s|MARIADB_DATABASE_PLACEHOLDER|$(MARIADB_DATABASE)|g" \
		-e "s|MARIADB_USER_PLACEHOLDER|$(MARIADB_USER)|g" \
		-e "s|WORDPRESS_RELEASE_PLACEHOLDER|$(WORDPRESS_RELEASE)|g" \
		-e "s|INGRESS_HOST_PLACEHOLDER|$(INGRESS_HOST)|g" \
		-e "s|MARIADB_IMAGE_PLACEHOLDER|$(MARIADB_IMAGE)|g" \
		-e "s|WORDPRESS_IMAGE_PLACEHOLDER|$(WORDPRESS_IMAGE)|g" \
		-e "s|NGINX_IMAGE_PLACEHOLDER|$(NGINX_IMAGE)|g" \
		$$file | kubectl delete -f - || true; \
	done
	@kubectl delete secret wordpress-secrets -n $(NAMESPACE) || true
	@echo "Deletion initiated. PVCs are retained by default."

# Clean up (deletes PVCs - CAUTION: DATA LOSS)
clean: check-prereqs
	@echo "WARNING: This will delete ALL WordPress resources AND PersistentVolumeClaims!"
	@echo "This will lead to DATA LOSS for your WordPress site and database."
	@read -p "Are you absolutely sure you want to proceed? (yes/no): " CONFIRMATION && \
	if [ "$$CONFIRMATION" = "yes" ]; then \
		$(MAKE) delete; \
		echo "Deleting PersistentVolumeClaims in namespace: $(NAMESPACE)..."; \
		kubectl delete pvc -l app=wordpress,tier=database -n $(NAMESPACE) || true; \
		kubectl delete pvc -l app=wordpress,tier=wordpress -n $(NAMESPACE) || true; \
		kubectl delete namespace $(NAMESPACE) || true; \
		echo "Cleanup complete. All resources and data associated with WordPress in namespace $(NAMESPACE) deleted."; \
	else \
		echo "Cleanup cancelled."; \
	fi