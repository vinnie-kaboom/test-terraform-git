# Alpine Linux-based Ansible image for reduced vulnerabilities
# Force rebuild: PyVmomi installation fix
FROM python:3.11-alpine

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    ANSIBLE_HOST_KEY_CHECKING=False \
    PYTHONPATH=/usr/local/lib/python3.11/site-packages

# Install all system dependencies in one layer
RUN apk update --no-cache && \
    apk upgrade --no-cache && \
    apk add --no-cache \
        openssh-client \
        git \
        ca-certificates \
        bash \
        sshpass \
        curl \
        unzip \
        gcc \
        musl-dev \
        libffi-dev \
        openssl-dev \
        python3-dev \
        py3-pip \
        # Additional dependencies for domain join operations
        krb5-dev \
        openldap-dev \
        samba-dev \
        # System utilities
        procps \
        net-tools \
        iputils \
        bind-tools \
        # Text processing
        grep \
        sed \
        gawk \
        jq && \
    # Ensure Python interpreter is properly configured
    ln -sf /usr/local/bin/python3 /usr/bin/python && \
    ln -sf /usr/local/bin/python3 /usr/bin/python3 && \
    ln -sf /usr/local/bin/python3 /usr/bin/python3.11 && \
    # Clean up package cache
    rm -rf /var/cache/apk/*

# Install Python packages in one layer with comprehensive parsers
RUN pip install --break-system-packages --no-cache-dir --upgrade "setuptools>=78.1.1" && \
    pip install --break-system-packages --no-cache-dir --upgrade pip && \
    pip install --break-system-packages --no-cache-dir "ansible==9.12.0" && \
    # Core dependencies
    pip install --break-system-packages --no-cache-dir requests urllib3 && \
    pip install --break-system-packages --no-cache-dir six pyvmomi==8.0.2.0.1 && \
    # YAML and INI parsing libraries
    pip install --break-system-packages --no-cache-dir PyYAML>=6.0 && \
    pip install --break-system-packages --no-cache-dir configparser2 && \
    pip install --break-system-packages --no-cache-dir iniparse && \
    # Additional parsing and utility libraries
    pip install --break-system-packages --no-cache-dir jinja2>=3.0 && \
    pip install --break-system-packages --no-cache-dir markupsafe>=2.0 && \
    pip install --break-system-packages --no-cache-dir cryptography>=3.4 && \
    pip install --break-system-packages --no-cache-dir paramiko>=2.8 && \
    pip install --break-system-packages --no-cache-dir netaddr>=0.8 && \
    pip install --break-system-packages --no-cache-dir dnspython>=2.2 && \
    # Domain join specific libraries
    pip install --break-system-packages --no-cache-dir ldap3>=2.9 && \
    pip install --break-system-packages --no-cache-dir python-ldap>=3.3 && \
    # Clean up pip cache
    rm -rf /root/.cache && \
    rm -rf /tmp/*

# Install Ansible collections for domain join automation
RUN ansible-galaxy collection install --force \
        community.windows:>=4.0.0 \
        community.general:>=5.0.0 \
        community.vmware:>=3.0.0 \
        ansible.posix:>=1.4.0 \
        ansible.utils:>=2.8.0

# Verify installations in one layer
RUN echo "=== Python Configuration ===" && \
    python --version && \
    python3 --version && \
    echo "Python path: $PYTHONPATH" && \
    echo "=== Python Modules ===" && \
    python -c "import requests; print('✅ requests module available')" && \
    python -c "import urllib3; print('✅ urllib3 module available')" && \
    python -c "import six; print('✅ six module available')" && \
    python -c "import pyVim; print('✅ pyVim module available')" && \
    python -c "import pyVmomi; print('✅ pyVmomi module available')" && \
    python -c "import yaml; print('✅ PyYAML module available')" && \
    python -c "import configparser; print('✅ configparser module available')" && \
    python -c "import iniparse; print('✅ iniparse module available')" && \
    python -c "import ldap3; print('✅ ldap3 module available')" && \
    python -c "import jinja2; print('✅ Jinja2 module available')" && \
    python -c "import cryptography; print('✅ cryptography module available')" && \
    python -c "import paramiko; print('✅ paramiko module available')" && \
    python -c "import netaddr; print('✅ netaddr module available')" && \
    python -c "import dns; print('✅ dnspython module available')" && \
    echo "=== Ansible Configuration ===" && \
    ansible --version && \
    echo "=== Installed Collections ===" && \
    ansible-galaxy collection list

# Create workspace directory and subdirectories
RUN mkdir -p /workspace/{logs,fact_cache,collections/offline} && \
    mkdir -p /workspace/.ansible/{tmp,cp} && \
    chmod 755 /workspace/.ansible

# Set working directory
WORKDIR /workspace

# Copy repository content (only what's needed)
COPY . /workspace/

# Create necessary directories and set permissions
RUN mkdir -p /workspace/logs /workspace/fact_cache && \
    chmod 755 /workspace/logs /workspace/fact_cache

# Install collections offline (for air-gapped environments)
RUN if [ -d "/workspace/collections/offline" ]; then \
        echo "Installing collections from offline directory..." && \
        for collection in /workspace/collections/offline/*.tar.gz; do \
            if [ -f "$collection" ]; then \
                echo "Installing: $collection" && \
                ansible-galaxy collection install "$collection" --force; \
            fi; \
        done; \
    else \
        echo "No offline collections directory found. Collections must be installed manually." && \
        echo "Expected location: /workspace/collections/offline/" && \
        echo "Expected format: collection-name-version.tar.gz"; \
    fi

# Create entrypoint script for better container management
RUN echo '#!/bin/bash' > /usr/local/bin/entrypoint.sh && \
    echo 'set -e' >> /usr/local/bin/entrypoint.sh && \
    echo '' >> /usr/local/bin/entrypoint.sh && \
    echo '# Function to display help' >> /usr/local/bin/entrypoint.sh && \
    echo 'show_help() {' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "=== Ansible Domain Join Automation Container ==="' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo ""' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "Available commands:"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  ansible-playbook    - Run Ansible playbooks"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  ansible            - Run Ansible commands"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  ansible-galaxy     - Manage collections and roles"' >> /usr/local/bin/entrypoint.sh && \
    echo '  help               - Show this help"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo ""' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "Examples:"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  docker run -it your-image ansible-playbook -i inventory/hosts.ini playbooks/site.yml"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  docker run -it your-image ansible --version"' >> /usr/local/bin/entrypoint.sh && \
    echo '  docker run -it your-image help"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo ""' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "Environment Variables:"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  ANSIBLE_HOST_KEY_CHECKING - SSH host key checking (default: False)"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  PYTHONPATH               - Python module path"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo ""' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "Volume Mounts:"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  -v /path/to/inventory:/workspace/inventory"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  -v /path/to/configs:/workspace/configs"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  -v /path/to/roles:/workspace/roles"' >> /usr/local/bin/entrypoint.sh && \
    echo '    echo "  -v /path/to/playbooks:/workspace/playbooks"' >> /usr/local/bin/entrypoint.sh && \
    echo '}' >> /usr/local/bin/entrypoint.sh && \
    echo '' >> /usr/local/bin/entrypoint.sh && \
    echo '# Main execution logic' >> /usr/local/bin/entrypoint.sh && \
    echo 'case "${1:-help}" in' >> /usr/local/bin/entrypoint.sh && \
    echo '    "help"|"--help"|"-h")' >> /usr/local/bin/entrypoint.sh && \
    echo '        show_help' >> /usr/local/bin/entrypoint.sh && \
    echo '        ;;' >> /usr/local/bin/entrypoint.sh && \
    echo '    "ansible-playbook"|"ansible"|"ansible-galaxy")' >> /usr/local/bin/entrypoint.sh && \
    echo '        exec "$@"' >> /usr/local/bin/entrypoint.sh && \
    echo '        ;;' >> /usr/local/bin/entrypoint.sh && \
    echo '    *)' >> /usr/local/bin/entrypoint.sh && \
    echo '        echo "Unknown command: $1"' >> /usr/local/bin/entrypoint.sh && \
    echo '        echo "Use help to see available commands"' >> /usr/local/bin/entrypoint.sh && \
    echo '        exit 1' >> /usr/local/bin/entrypoint.sh && \
    echo '        ;;' >> /usr/local/bin/entrypoint.sh && \
    echo 'esac' >> /usr/local/bin/entrypoint.sh

# Make entrypoint script executable
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set entrypoint and default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["help"]