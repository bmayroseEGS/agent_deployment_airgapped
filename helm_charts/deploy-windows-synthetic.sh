#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/windows-synthetic-agent"
NAMESPACE="elastic"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Windows Synthetic Data Generator${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Generates fake Windows event logs and sends"
echo "them directly to Elasticsearch via Bulk API."
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl found${NC}"

# Check helm
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ helm found${NC}"

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Kubernetes cluster accessible${NC}"

# Check if namespace exists
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    echo -e "${RED}Error: Namespace '${NAMESPACE}' does not exist${NC}"
    echo -e "${YELLOW}Create it with: kubectl create namespace ${NAMESPACE}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Namespace '${NAMESPACE}' exists${NC}"

# Check Elasticsearch
echo ""
echo -e "${YELLOW}Checking Elasticsearch...${NC}"
ES_POD=$(kubectl get pods -n ${NAMESPACE} -l app=elasticsearch-master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$ES_POD" ]; then
    echo -e "${RED}Warning: Elasticsearch pod not found${NC}"
    echo -e "${YELLOW}The generator will attempt to connect to http://elasticsearch-master:9200${NC}"
else
    echo -e "${GREEN}✓ Elasticsearch found: ${ES_POD}${NC}"
fi

# Check required images in registry
echo ""
echo -e "${YELLOW}Checking required images in registry...${NC}"

check_image() {
    local image=$1
    if curl -s "http://localhost:5000/v2/${image}/tags/list" | grep -q "tags"; then
        echo -e "${GREEN}✓ Found: ${image}${NC}"
        return 0
    else
        echo -e "${RED}✗ Missing: ${image}${NC}"
        return 1
    fi
}

IMAGES_OK=true
check_image "python" || IMAGES_OK=false

if [ "$IMAGES_OK" = false ]; then
    echo ""
    echo -e "${YELLOW}Python image is missing from the local registry.${NC}"
    echo -e "${YELLOW}Please load it before deploying:${NC}"
    echo ""
    echo "  # On internet-connected machine:"
    echo "  docker pull python:3.11-slim"
    echo "  docker tag python:3.11-slim localhost:5000/python:3.11-slim"
    echo "  docker save localhost:5000/python:3.11-slim -o python-slim.tar"
    echo ""
    echo "  # On air-gapped machine:"
    echo "  docker load -i python-slim.tar && docker push localhost:5000/python:3.11-slim"
    echo ""
    read -p "Continue anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 1
    fi
fi

# Configuration options
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Configuration${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Events per minute
read -p "Events per minute [60]: " EVENTS_PER_MIN
EVENTS_PER_MIN=${EVENTS_PER_MIN:-60}

# Generation mode
echo ""
echo "Generation mode:"
echo "  1) continuous - Generate events continuously"
echo "  2) batch - Generate events in batches with pauses"
read -p "Select mode [1]: " MODE_CHOICE
MODE_CHOICE=${MODE_CHOICE:-1}
if [ "$MODE_CHOICE" = "2" ]; then
    GEN_MODE="batch"
else
    GEN_MODE="continuous"
fi

# Custom values file
echo ""
read -p "Use custom values file? (path or empty): " CUSTOM_VALUES
VALUES_ARG=""
if [ -n "$CUSTOM_VALUES" ] && [ -f "$CUSTOM_VALUES" ]; then
    VALUES_ARG="-f ${CUSTOM_VALUES}"
fi

# Check for existing deployment
echo ""
echo -e "${YELLOW}Checking for existing deployment...${NC}"
if helm list -n ${NAMESPACE} | grep -q "windows-synthetic"; then
    echo -e "${YELLOW}Existing deployment found.${NC}"
    read -p "Upgrade existing deployment? (y/n) [y]: " UPGRADE
    UPGRADE=${UPGRADE:-y}
    if [ "$UPGRADE" = "y" ]; then
        HELM_CMD="upgrade"
    else
        echo -e "${YELLOW}Uninstalling existing deployment...${NC}"
        helm uninstall windows-synthetic -n ${NAMESPACE}
        sleep 5
        HELM_CMD="install"
    fi
else
    HELM_CMD="install"
fi

# Deploy
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Deploying Windows Synthetic Generator${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

HELM_FULL_CMD="helm ${HELM_CMD} windows-synthetic ${CHART_DIR} \
    -n ${NAMESPACE} \
    --set generator.eventsPerMinute=${EVENTS_PER_MIN} \
    --set generator.mode=${GEN_MODE} \
    ${VALUES_ARG}"

echo -e "${YELLOW}Running: ${HELM_FULL_CMD}${NC}"
echo ""

eval $HELM_FULL_CMD

if [ $? -ne 0 ]; then
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Deployment initiated successfully!${NC}"

# Wait for pod
echo ""
echo -e "${YELLOW}Waiting for pod to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=windows-synthetic-agent -n ${NAMESPACE} --timeout=120s

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Pod is ready!${NC}"
else
    echo -e "${YELLOW}Pod not ready yet. Check status with:${NC}"
    echo "  kubectl get pods -n ${NAMESPACE} -l app=windows-synthetic-agent"
fi

# Show status
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Deployment Status${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
kubectl get pods -n ${NAMESPACE} -l app=windows-synthetic-agent

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Next Steps${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "1. View generator logs:"
echo "   kubectl logs -n ${NAMESPACE} -l app=windows-synthetic-agent -f"
echo ""
echo "2. Data streams created:"
echo "   - logs-windows.security-default"
echo "   - logs-windows.system-default"
echo "   - logs-windows.application-default"
echo ""
echo "3. View data in Kibana:"
echo "   - Go to Discover"
echo "   - Select 'logs-windows.*' data view"
echo "   - Filter by labels.synthetic: true to see only synthetic events"
echo ""
echo "4. Uninstall:"
echo "   helm uninstall windows-synthetic -n ${NAMESPACE}"
echo ""
