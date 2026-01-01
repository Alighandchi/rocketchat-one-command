Replace the install_docker function with this improved version:
bashinstall_docker() {
    print_step "Installing/Updating Docker..."
    
    if command -v docker &> /dev/null; then
        local current_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        print_info "Docker is already installed (version: $current_version)"
        print_info "Updating Docker to latest version..."
    else
        print_info "Docker not found. Installing..."
    fi
    
    case $PKG_MANAGER in
        apt)
            # Clean up any existing Docker repository configurations first
            rm -f /etc/apt/sources.list.d/docker.list
            rm -f /etc/apt/sources.list.d/docker.sources
            rm -f /etc/apt/keyrings/docker.gpg
            rm -f /etc/apt/keyrings/docker.asc
            
            # Remove old versions
            apt remove -y docker docker-engine docker.io containerd runc &> /dev/null || true
            
            # Method 1: Try official repository first
            print_info "Attempting Docker installation from official repository..."
            
            # Add Docker's official GPG key
            install -m 0755 -d /etc/apt/keyrings
            
            if curl -fsSL https://download.docker.com/linux/$DISTRO/gpg -o /etc/apt/keyrings/docker.asc 2>/dev/null; then
                chmod a+r /etc/apt/keyrings/docker.asc
                
                # Add Docker repository using new format
                cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$DISTRO
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
                
                # Try to update and install
                apt update -qq 2>&1 | grep -v "Failed to fetch" | grep -v "403" || true
                
                if apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | grep -q "Unable to locate"; then
                    print_warning "Official repository blocked or unavailable"
                    print_info "Trying alternative installation method..."
                    
                    # Clean up failed attempt
                    rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
                    
                    # Method 2: Install from Ubuntu repository
                    print_info "Installing Docker from Ubuntu repository..."
                    apt update -qq
                    apt install -y docker.io docker-compose -qq
                    
                    # Create docker compose plugin symlink for compatibility
                    mkdir -p /usr/local/lib/docker/cli-plugins
                    ln -sf /usr/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose 2>/dev/null || true
                    
                    print_success "Docker installed from Ubuntu repository"
                else
                    print_success "Docker installed from official repository"
                fi
            else
                print_warning "Cannot access Docker official repository (possibly blocked)"
                print_info "Installing Docker from Ubuntu repository..."
                
                # Clean up
                rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
                
                apt update -qq
                apt install -y docker.io docker-compose -qq
                
                # Create docker compose plugin symlink for compatibility
                mkdir -p /usr/local/lib/docker/cli-plugins
                ln -sf /usr/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose 2>/dev/null || true
                
                print_success "Docker installed from Ubuntu repository"
            fi
            ;;
        dnf|yum)
            # Remove old versions
            $PKG_MANAGER remove -y docker docker-client docker-client-latest docker-common docker-latest \
                docker-latest-logrotate docker-logrotate docker-engine &> /dev/null || true
            
            print_info "Attempting Docker installation from official repository..."
            
            # Add Docker repository
            if $PKG_MANAGER install -y yum-utils &> /dev/null && \
               yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &> /dev/null; then
                
                # Try to install
                if $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &> /dev/null; then
                    print_success "Docker installed from official repository"
                else
                    print_warning "Official repository blocked or unavailable"
                    print_info "Installing Docker from system repository..."
                    
                    $PKG_MANAGER install -y docker docker-compose &> /dev/null
                    print_success "Docker installed from system repository"
                fi
            else
                print_warning "Cannot access Docker official repository"
                print_info "Installing Docker from system repository..."
                
                $PKG_MANAGER install -y docker docker-compose &> /dev/null
                print_success "Docker installed from system repository"
            fi
            ;;
    esac
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker &> /dev/null
    
    # Configure Docker registry mirror if provided
    if [ -n "$DOCKER_REGISTRY_MIRROR" ]; then
        print_info "Configuring Docker registry mirror..."
        
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$DOCKER_REGISTRY_MIRROR"]
}
EOF
        
        systemctl restart docker
        print_success "Docker registry mirror configured"
    fi
    
    # Verify installation
    if ! command -v docker &> /dev/null; then
        print_error "Docker installation failed"
        exit 1
    fi
    
    local new_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    print_success "Docker installed/updated (version: $new_version)"
    
    # Check for docker compose (plugin or standalone)
    if docker compose version &> /dev/null; then
        print_success "Docker Compose (plugin) is available"
    elif command -v docker-compose &> /dev/null; then
        print_success "Docker Compose (standalone) is available"
        print_info "Note: Using 'docker-compose' command instead of 'docker compose'"
    else
        print_error "Docker Compose is not available"
        exit 1
    fi
}