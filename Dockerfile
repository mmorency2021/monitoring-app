# Rootless Monitoring Agent - Dockerfile
# Demonstrates how to build a non-root container for monitoring

FROM python:3.11-slim

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    procps \
    net-tools \
    libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir \
    psutil==5.9.8

# Create non-root user
# This is CRITICAL - never run as root
RUN groupadd -g 1000 monitor && \
    useradd -u 1000 -g monitor -s /bin/bash -m monitor

# Create directories with proper permissions
RUN mkdir -p /app /tmp /var/log/monitor && \
    chown -R monitor:monitor /app /tmp /var/log/monitor

# Copy application code
COPY --chown=monitor:monitor monitor.py /app/

# Make script executable
RUN chmod +x /app/monitor.py

# Set working directory
WORKDIR /app

# Switch to non-root user
USER monitor

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD test -f /tmp/metrics.json || exit 1

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    MONITOR_INTERVAL=30

# Run the monitor
ENTRYPOINT ["python3", "/app/monitor.py"]
