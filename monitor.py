#!/usr/bin/env python3
"""
Rootless Node Monitoring Agent
Demonstrates EDR-like monitoring without root privileges

This agent monitors:
- Process events via /proc filesystem
- Network connections
- Container logs
- System metrics

All without requiring root user or privileged containers.
"""

import os
import sys
import time
import json
import socket
import psutil
import logging
from datetime import datetime
from pathlib import Path
from collections import defaultdict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('rootless-monitor')


class RootlessMonitor:
    """Node monitoring agent running as non-root user"""

    def __init__(self):
        self.hostname = socket.gethostname()
        self.node_name = os.getenv('NODE_NAME', self.hostname)
        self.namespace = os.getenv('POD_NAMESPACE', 'default')
        self.pod_name = os.getenv('POD_NAME', 'unknown')

        # Host paths (mounted read-only)
        self.host_proc = Path('/host/proc')
        self.host_sys = Path('/host/sys')

        # Metrics storage
        self.process_count = 0
        self.connection_count = 0
        self.monitored_pids = set()

        logger.info(f"Starting Rootless Monitor Agent")
        logger.info(f"  Node: {self.node_name}")
        logger.info(f"  Namespace: {self.namespace}")
        logger.info(f"  Pod: {self.pod_name}")
        logger.info(f"  Running as UID: {os.getuid()}")
        logger.info(f"  Running as GID: {os.getgid()}")

        # Verify we're NOT running as root
        if os.getuid() == 0:
            logger.error("ERROR: Running as root! This defeats the purpose.")
            sys.exit(1)

    def check_capabilities(self):
        """Check what Linux capabilities are available"""
        logger.info("Checking available capabilities...")

        # Try to read capabilities from /proc/self/status
        try:
            with open('/proc/self/status', 'r') as f:
                for line in f:
                    if line.startswith('Cap'):
                        logger.info(f"  {line.strip()}")
        except Exception as e:
            logger.warning(f"Could not read capabilities: {e}")

    def monitor_processes(self):
        """Monitor running processes via /proc filesystem"""
        logger.info("=== Process Monitoring ===")

        try:
            # Read from host /proc (mounted as /host/proc)
            if self.host_proc.exists():
                proc_dirs = [d for d in self.host_proc.iterdir() if d.is_dir() and d.name.isdigit()]

                new_processes = []
                for proc_dir in proc_dirs:
                    try:
                        pid = int(proc_dir.name)

                        # Skip if already monitored
                        if pid in self.monitored_pids:
                            continue

                        # Read process info
                        cmdline_file = proc_dir / 'cmdline'
                        if cmdline_file.exists():
                            with open(cmdline_file, 'rb') as f:
                                cmdline = f.read().decode('utf-8', errors='ignore')
                                cmdline = cmdline.replace('\x00', ' ').strip()

                                if cmdline:  # Only track processes with command line
                                    new_processes.append({
                                        'pid': pid,
                                        'cmdline': cmdline[:100],  # Truncate long commands
                                        'timestamp': datetime.now().isoformat()
                                    })
                                    self.monitored_pids.add(pid)

                    except (PermissionError, FileNotFoundError):
                        # Expected for some processes we can't read
                        continue
                    except Exception as e:
                        logger.debug(f"Error reading process {proc_dir.name}: {e}")

                if new_processes:
                    logger.info(f"Detected {len(new_processes)} new processes:")
                    for proc in new_processes[:5]:  # Show first 5
                        logger.info(f"  PID {proc['pid']}: {proc['cmdline']}")
                    if len(new_processes) > 5:
                        logger.info(f"  ... and {len(new_processes) - 5} more")

                self.process_count = len(self.monitored_pids)
                logger.info(f"Total processes tracked: {self.process_count}")

            else:
                logger.warning(f"Host /proc not mounted at {self.host_proc}")

        except Exception as e:
            logger.error(f"Error monitoring processes: {e}")

    def monitor_network(self):
        """Monitor network connections"""
        logger.info("=== Network Monitoring ===")

        try:
            # Get network connections using psutil
            # Note: This may require CAP_NET_RAW for raw sockets
            connections = psutil.net_connections(kind='inet')

            # Group by state
            conn_by_state = defaultdict(int)
            for conn in connections:
                conn_by_state[conn.status] += 1

            logger.info(f"Network connections by state:")
            for state, count in sorted(conn_by_state.items()):
                logger.info(f"  {state}: {count}")

            self.connection_count = len(connections)

            # Show listening ports
            listening = [c for c in connections if c.status == 'LISTEN']
            if listening:
                logger.info(f"Listening ports: {len(listening)}")
                for conn in listening[:10]:  # Show first 10
                    logger.info(f"  {conn.laddr.ip}:{conn.laddr.port}")

        except PermissionError:
            logger.warning("Network monitoring requires CAP_NET_RAW capability")
        except Exception as e:
            logger.error(f"Error monitoring network: {e}")

    def monitor_system_metrics(self):
        """Monitor system-level metrics"""
        logger.info("=== System Metrics ===")

        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            logger.info(f"CPU Usage: {cpu_percent}%")

            # Memory usage
            memory = psutil.virtual_memory()
            logger.info(f"Memory Usage: {memory.percent}% ({memory.used / 1024**3:.2f}GB / {memory.total / 1024**3:.2f}GB)")

            # Disk usage
            disk = psutil.disk_usage('/')
            logger.info(f"Disk Usage: {disk.percent}% ({disk.used / 1024**3:.2f}GB / {disk.total / 1024**3:.2f}GB)")

            # Network I/O
            net_io = psutil.net_io_counters()
            logger.info(f"Network I/O: {net_io.bytes_sent / 1024**2:.2f}MB sent, {net_io.bytes_recv / 1024**2:.2f}MB received")

        except Exception as e:
            logger.error(f"Error monitoring system metrics: {e}")

    def check_security_events(self):
        """Simulate security event detection"""
        logger.info("=== Security Event Detection ===")

        # Example: Check for suspicious process patterns
        suspicious_patterns = [
            'nc -l',          # Netcat listener
            '/dev/tcp',       # Bash reverse shell
            'wget http',      # Downloads
            'curl http',      # Downloads
            'chmod 777',      # Dangerous permissions
        ]

        alerts = []

        try:
            if self.host_proc.exists():
                for proc_dir in self.host_proc.iterdir():
                    if not proc_dir.is_dir() or not proc_dir.name.isdigit():
                        continue

                    try:
                        cmdline_file = proc_dir / 'cmdline'
                        if cmdline_file.exists():
                            with open(cmdline_file, 'rb') as f:
                                cmdline = f.read().decode('utf-8', errors='ignore')

                                for pattern in suspicious_patterns:
                                    if pattern in cmdline:
                                        alerts.append({
                                            'pid': proc_dir.name,
                                            'pattern': pattern,
                                            'cmdline': cmdline[:100]
                                        })

                    except (PermissionError, FileNotFoundError):
                        continue

        except Exception as e:
            logger.error(f"Error checking security events: {e}")

        if alerts:
            logger.warning(f"⚠️  SECURITY ALERTS: {len(alerts)} suspicious patterns detected!")
            for alert in alerts[:5]:
                logger.warning(f"  PID {alert['pid']}: {alert['pattern']}")
        else:
            logger.info("✅ No suspicious patterns detected")

    def export_metrics(self):
        """Export metrics in JSON format"""
        metrics = {
            'timestamp': datetime.now().isoformat(),
            'node': self.node_name,
            'namespace': self.namespace,
            'pod': self.pod_name,
            'metrics': {
                'processes_tracked': self.process_count,
                'network_connections': self.connection_count,
                'cpu_percent': psutil.cpu_percent(),
                'memory_percent': psutil.virtual_memory().percent,
                'disk_percent': psutil.disk_usage('/').percent
            }
        }

        # Write to file (in tmpfs volume)
        metrics_file = Path('/tmp/metrics.json')
        with open(metrics_file, 'w') as f:
            json.dump(metrics, f, indent=2)

        logger.info(f"Metrics exported to {metrics_file}")
        return metrics

    def run_monitoring_cycle(self):
        """Run one complete monitoring cycle"""
        logger.info("\n" + "="*60)
        logger.info(f"Monitoring Cycle - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        logger.info("="*60)

        self.check_capabilities()
        self.monitor_processes()
        self.monitor_network()
        self.monitor_system_metrics()
        self.check_security_events()
        metrics = self.export_metrics()

        logger.info("\n" + "="*60)
        logger.info("Cycle Complete")
        logger.info("="*60 + "\n")

        return metrics


def main():
    """Main entry point"""
    logger.info("="*60)
    logger.info("Rootless Node Monitoring Agent - Starting")
    logger.info("="*60)

    # Verify we're running as non-root
    if os.getuid() == 0:
        logger.error("FATAL: This agent must NOT run as root!")
        logger.error("Please configure securityContext.runAsUser to a non-zero UID")
        sys.exit(1)

    # Create monitor instance
    monitor = RootlessMonitor()

    # Get monitoring interval from environment
    interval = int(os.getenv('MONITOR_INTERVAL', '30'))
    logger.info(f"Monitoring interval: {interval} seconds")

    # Main monitoring loop
    cycle_count = 0
    try:
        while True:
            cycle_count += 1
            logger.info(f"\n{'#'*60}")
            logger.info(f"# Cycle {cycle_count}")
            logger.info(f"{'#'*60}")

            monitor.run_monitoring_cycle()

            logger.info(f"Sleeping for {interval} seconds...")
            time.sleep(interval)

    except KeyboardInterrupt:
        logger.info("\nShutdown signal received")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)
    finally:
        logger.info("Rootless Monitor Agent stopped")


if __name__ == '__main__':
    main()
