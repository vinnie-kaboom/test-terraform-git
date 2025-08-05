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
        podman && \
    # Create Docker alias for Podman
    ln -sf /usr/bin/podman /usr/bin/docker && \
    echo '#!/bin/sh' > /usr/local/bin/docker && \
    echo 'exec /usr/bin/podman "$@"' >> /usr/local/bin/docker && \
    chmod +x /usr/local/bin/docker && \
    # Ensure Python interpreter is properly configured
    ln -sf /usr/local/bin/python3 /usr/bin/python && \
    ln -sf /usr/local/bin/python3 /usr/bin/python3 && \
    ln -sf /usr/local/bin/python3 /usr/bin/python3.12 && \
    # Clean up package cache
    rm -rf /var/cache/apk/*

# Install Python packages in one layer
RUN pip install --break-system-packages --no-cache-dir --upgrade "setuptools>=78.1.1" && \
    pip install --break-system-packages --no-cache-dir --upgrade pip && \
    pip install --break-system-packages --no-cache-dir "ansible==9.12.0" && \
    pip install --break-system-packages --no-cache-dir requests urllib3 && \
    pip install --break-system-packages --no-cache-dir six pyvmomi==8.0.2.0.1 && \
    ansible-galaxy collection install community.vmware && \
    # Clean up pip cache
    rm -rf /root/.cache && \
    rm -rf /tmp/*

    RUN ansible-galaxy collection install -f community.vmware && \
    ansible-galaxy collection list | grep vmware


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
    echo "=== Ansible Configuration ===" && \
    ansible --version && \
    echo "=== Container Tools ===" && \
    podman --version

# Create workspace directory
RUN mkdir -p /workspace

# Set working directory
WORKDIR /workspace

# Copy repository content (only what's needed)
COPY . /workspace/

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ansible --version || exit 1

# Default command
CMD ["ansible", "--version"]