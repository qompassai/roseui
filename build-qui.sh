#!/bin/bash

# Function to extract values from parameters
extract_value() {
    echo "$1" | sed -E 's/^[^=]+=(.*)/\1/'
}

# Default values
enable_gpu=false
enable_api=false
api_port=11435
webui_port=3000
data_dir="./ollama-data"
enable_playwright=false
kill_compose=false
build_image=false
headless=false

# Function to display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --enable-gpu[=COUNT]   Enable GPU support (default count: 1)"
    echo "  --enable-api[=PORT]    Enable API support (default port: 11435)"
    echo "  --webui=PORT           Set WebUI port (default: 3000)"
    echo "  --data=DIR             Set data directory (default: ./ollama-data)"
    echo "  --playwright           Enable Playwright for testing"
    echo "  --drop                 Kill existing Docker Compose setup"
    echo "  --build                Build the Docker images"
    echo "  -q, --quiet            Run in headless mode"
    echo "  -h, --help             Display this help message"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --enable-gpu*)
            enable_gpu=true
            value=$(extract_value "$key")
            gpu_count=${value:-1}
            ;;
        --enable-api*)
            enable_api=true
            value=$(extract_value "$key")
            api_port=${value:-11435}
            ;;
        --webui*)
            value=$(extract_value "$key")
            webui_port=${value:-3000}
            ;;
        --data*)
            value=$(extract_value "$key")
            data_dir=${value:-"./ollama-data"}
            ;;
        --playwright)
            enable_playwright=true
            ;;
        --drop)
            kill_compose=true
            ;;
        --build)
            build_image=true
            ;;
        -q|--quiet)
            headless=true
            ;;
        -h|--help)
            usage
            exit
            ;;
        *)
            # Unknown option
            echo "Unknown option: $key"
            usage
            exit 1
            ;;
    esac
    shift
done

# Build logic
project_name="qui"

# Kill existing setup if requested
if [ "$kill_compose" = true ]; then
    echo "Stopping existing Docker Compose setup..."
    docker-compose -p $project_name down
fi

# Configure docker-compose command
compose_cmd="docker-compose -p $project_name"

# Handle GPU support
if [ "$enable_gpu" = true ]; then
    echo "Enabling GPU support with $gpu_count GPU(s)..."
    # Add GPU configuration to environment variables
    export NVIDIA_VISIBLE_DEVICES=all
    export NVIDIA_DRIVER_CAPABILITIES=compute,utility
fi

# Modify ports if needed
if [ "$enable_api" = true ]; then
    echo "Enabling API on port $api_port..."
    export API_PORT=$api_port
fi

echo "Setting WebUI port to $webui_port..."
export WEBUI_PORT=$webui_port

echo "Setting data directory to $data_dir..."
export DATA_DIR=$data_dir

# Build images if requested
if [ "$build_image" = true ]; then
    echo "Building Docker images..."
    $compose_cmd build
fi

# Start the containers
echo "Starting Docker Compose setup as project '$project_name'..."
$compose_cmd up -d

echo "Setup complete. Open WebUI available at http://localhost:$webui_port"

