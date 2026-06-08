#!/bin/bash
echo "=== DaemonSet Status ==="
oc get ds -n rootless-monitor rootless-monitor-minimal -o wide

echo -e "\n=== DaemonSet Events ==="
oc describe ds -n rootless-monitor rootless-monitor-minimal | tail -20

echo -e "\n=== Pods in Namespace ==="
oc get pods -n rootless-monitor

echo -e "\n=== ReplicaSets (if any) ==="
oc get rs -n rootless-monitor

echo -e "\n=== Namespace Events ==="
oc get events -n rootless-monitor --sort-by='.lastTimestamp' | tail -20

echo -e "\n=== Check if namespace has Pod Security labels ==="
oc get namespace rootless-monitor -o yaml | grep -A 3 "pod-security"
