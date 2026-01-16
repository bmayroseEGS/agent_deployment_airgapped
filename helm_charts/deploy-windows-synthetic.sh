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
echo -e "${BLUE}  Windows Synthetic Agent Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
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
    echo -e "${YELLOW}The agent will attempt to connect to http://elasticsearch-master:9200${NC}"
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
check_image "elastic-agent/elastic-agent" || IMAGES_OK=false
check_image "python" || IMAGES_OK=false
check_image "busybox" || IMAGES_OK=false

if [ "$IMAGES_OK" = false ]; then
    echo ""
    echo -e "${YELLOW}Some images are missing from the local registry.${NC}"
    echo -e "${YELLOW}Please load them before deploying:${NC}"
    echo ""
    echo "  # On internet-connected machine:"
    echo "  docker pull python:3.11-slim"
    echo "  docker tag python:3.11-slim localhost:5000/library/python:3.11-slim"
    echo "  docker save localhost:5000/library/python:3.11-slim -o python-slim.tar"
    echo ""
    echo "  docker pull busybox:1.36"
    echo "  docker tag busybox:1.36 localhost:5000/library/busybox:1.36"
    echo "  docker save localhost:5000/library/busybox:1.36 -o busybox.tar"
    echo ""
    echo "  # On air-gapped machine:"
    echo "  docker load -i python-slim.tar && docker push localhost:5000/library/python:3.11-slim"
    echo "  docker load -i busybox.tar && docker push localhost:5000/library/busybox:1.36"
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

# Fleet mode
echo ""
read -p "Use Fleet-managed mode? (y/n) [n]: " USE_FLEET
USE_FLEET=${USE_FLEET:-n}

FLEET_ARGS=""
if [ "$USE_FLEET" = "y" ]; then
    read -p "Fleet enrollment token: " FLEET_TOKEN
    if [ -z "$FLEET_TOKEN" ]; then
        echo -e "${RED}Error: Fleet enrollment token is required for Fleet mode${NC}"
        exit 1
    fi
    FLEET_ARGS="--set fleet.enabled=true --set fleet.enrollmentToken=${FLEET_TOKEN}"
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
echo -e "${BLUE}  Deploying Windows Synthetic Agent${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

HELM_FULL_CMD="helm ${HELM_CMD} windows-synthetic ${CHART_DIR} \
    -n ${NAMESPACE} \
    --set generator.eventsPerMinute=${EVENTS_PER_MIN} \
    --set generator.mode=${GEN_MODE} \
    ${FLEET_ARGS} \
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
echo "   kubectl logs -n ${NAMESPACE} -l app=windows-synthetic-agent -c windows-event-generator -f"
echo ""
echo "2. View agent logs:"
echo "   kubectl logs -n ${NAMESPACE} -l app=windows-synthetic-agent -c elastic-agent -f"
echo ""
echo "3. View data in Kibana:"
echo "   - Go to Discover"
echo "   - Create index pattern: logs-windows.synthetic-*"
echo "   - Search for winlog.event_id field"
echo ""
echo "4. Uninstall:"
echo "   helm uninstall windows-synthetic -n ${NAMESPACE}"
echo ""
