#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="elastic"
RELEASE_NAME="elastic-agent"
CHART_PATH="./elastic-agent"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Elastic Agent Deployment Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "$1"
}

# Check prerequisites
echo "Checking prerequisites..."

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed"
    exit 1
fi
print_success "kubectl is installed"

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    print_error "helm is not installed"
    exit 1
fi
print_success "helm is installed"

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi
print_success "Connected to Kubernetes cluster"

# Check if Elasticsearch is running
echo ""
echo "Checking Elastic Stack components..."
if ! kubectl get pods -n ${NAMESPACE} -l app=elasticsearch &> /dev/null; then
    print_warning "Elasticsearch pods not found in namespace '${NAMESPACE}'"
    read -p "Continue anyway? (y/n): " continue_without_es
    if [[ ! $continue_without_es =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_success "Elasticsearch is running"
fi

# Check if Kibana is running
if ! kubectl get pods -n ${NAMESPACE} -l app=kibana &> /dev/null; then
    print_warning "Kibana pods not found in namespace '${NAMESPACE}'"
else
    print_success "Kibana is running"
fi

# Check if Fleet Server is running
if kubectl get pods -n ${NAMESPACE} -l app=fleet-server &> /dev/null; then
    print_success "Fleet Server is running"
    FLEET_AVAILABLE=true
else
    print_warning "Fleet Server not found (optional)"
    FLEET_AVAILABLE=false
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Configuration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Ask for deployment mode
read -p "Deployment mode (daemonset/deployment) [daemonset]: " deployment_mode
deployment_mode=${deployment_mode:-daemonset}

# Set helm arguments
HELM_ARGS="--namespace ${NAMESPACE} --create-namespace"

if [ "$deployment_mode" == "deployment" ]; then
    read -p "Number of replicas [1]: " replicas
    replicas=${replicas:-1}
    HELM_ARGS="${HELM_ARGS} --set deploymentMode=deployment --set replicas=${replicas}"
else
    HELM_ARGS="${HELM_ARGS} --set deploymentMode=daemonset"
fi

# Ask about Fleet Server enrollment
if [ "$FLEET_AVAILABLE" = true ]; then
    echo ""
    read -p "Use Fleet Server for agent management? (y/n) [n]: " use_fleet
    if [[ $use_fleet =~ ^[Yy]$ ]]; then
        print_info ""
        print_info "To get the enrollment token:"
        print_info "1. Open Kibana: http://localhost:5601"
        print_info "2. Go to Fleet → Enrollment tokens"
        print_info "3. Copy the token for your agent policy"
        print_info ""
        read -p "Enter Fleet enrollment token: " enrollment_token

        if [ -n "$enrollment_token" ]; then
            HELM_ARGS="${HELM_ARGS} --set fleet.enabled=true --set fleet.enrollmentToken=${enrollment_token}"
            print_success "Fleet enrollment configured"
        else
            print_warning "No enrollment token provided, using standalone mode"
            HELM_ARGS="${HELM_ARGS} --set fleet.enabled=false"
        fi
    else
        HELM_ARGS="${HELM_ARGS} --set fleet.enabled=false"
    fi
else
    HELM_ARGS="${HELM_ARGS} --set fleet.enabled=false"
fi

# Ask about custom values file
echo ""
read -p "Use custom values file? (y/n) [n]: " use_custom_values
if [[ $use_custom_values =~ ^[Yy]$ ]]; then
    read -p "Enter path to values file: " values_file
    if [ -f "$values_file" ]; then
        HELM_ARGS="${HELM_ARGS} -f ${values_file}"
        print_success "Custom values file: ${values_file}"
    else
        print_error "Values file not found: ${values_file}"
        exit 1
    fi
fi

# Display deployment summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Namespace:       ${NAMESPACE}"
echo "Release Name:    ${RELEASE_NAME}"
echo "Chart Path:      ${CHART_PATH}"
echo "Deployment Mode: ${deployment_mode}"
if [ "$deployment_mode" == "deployment" ]; then
    echo "Replicas:        ${replicas}"
fi
echo ""

# Confirm deployment
read -p "Proceed with deployment? (y/n): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled"
    exit 0
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deploying Elastic Agent${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Run helm install/upgrade
echo "Running: helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} ${HELM_ARGS}"
if helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} ${HELM_ARGS}; then
    print_success "Helm deployment successful"
else
    print_error "Helm deployment failed"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Verifying Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Wait for pods to be ready
echo "Waiting for agent pods to be ready..."
sleep 5

if [ "$deployment_mode" == "daemonset" ]; then
    kubectl rollout status daemonset/${RELEASE_NAME} -n ${NAMESPACE} --timeout=120s
else
    kubectl rollout status deployment/${RELEASE_NAME} -n ${NAMESPACE} --timeout=120s
fi

# Show pod status
echo ""
print_success "Deployment complete!"
echo ""
echo "Agent pods:"
kubectl get pods -n ${NAMESPACE} -l app=elastic-agent

# Show logs
echo ""
read -p "Show agent logs? (y/n) [y]: " show_logs
show_logs=${show_logs:-y}
if [[ $show_logs =~ ^[Yy]$ ]]; then
    echo ""
    echo "Agent logs (last 50 lines):"
    kubectl logs -n ${NAMESPACE} -l app=elastic-agent --tail=50
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Next Steps${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
print_info "1. Check agent status:"
print_info "   kubectl get pods -n ${NAMESPACE} -l app=elastic-agent"
echo ""
print_info "2. View agent logs:"
print_info "   kubectl logs -n ${NAMESPACE} -l app=elastic-agent -f"
echo ""
print_info "3. Verify data in Kibana:"
print_info "   http://localhost:5601/app/discover"
echo ""
if [[ $use_fleet =~ ^[Yy]$ ]]; then
    print_info "4. Check Fleet enrollment:"
    print_info "   http://localhost:5601/app/fleet/agents"
    echo ""
fi
print_info "To uninstall:"
print_info "   helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
echo ""

print_success "Deployment successful!"
