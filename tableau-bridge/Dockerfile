# ==============================================================================
# Tableau Bridge for Linux (Docker / Kubernetes HA Deployment)
# Base OS: Red Hat Universal Base Image 8 (UBI 8) - x86_64 Architecture
# ==============================================================================
FROM --platform=linux/amd64 registry.access.redhat.com/ubi8/ubi:8.9

LABEL maintainer="DevOps Team"
LABEL description="Tableau Bridge Container with MySQL 8 Driver for K8s HA Deployment"

# 1. Install prerequisites and dependencies required by Tableau Bridge & ODBC
RUN yum -y update && \
    yum -y install \
      ca-certificates \
      wget \
      curl \
      tar \
      gzip \
      unixODBC \
      unixODBC-devel \
      glibc-langpack-en \
      hostname \
    && yum clean all

# 2. Download and install MySQL Connector/ODBC 8.0 for RedHat 8 (x86_64)
RUN (wget --no-check-certificate --tries=5 --timeout=30 https://downloads.mysql.com/archives/get/p/10/file/mysql-connector-odbc-8.0.33-1.el8.x86_64.rpm -O /tmp/mysql-connector.rpm || \
     wget --no-check-certificate --tries=5 --timeout=30 https://repo.mysql.com/yum/mysql-8.0-community/el/8/x86_64/mysql-connector-odbc-8.0.35-1.el8.x86_64.rpm -O /tmp/mysql-connector.rpm) && \
    rpm -ivh --nodeps /tmp/mysql-connector.rpm && \
    rm -f /tmp/mysql-connector.rpm

# 3. Copy Tableau Bridge RPM package into container
# Download the RPM from Tableau: https://www.tableau.com/support/downloads/bridge
ARG TABLEAU_BRIDGE_RPM=TableauBridge-2024.1.0-x86_64.rpm
COPY ${TABLEAU_BRIDGE_RPM} /tmp/tableau-bridge.rpm

# Install Tableau Bridge accepting EULA
RUN ACCEPT_EULA=y yum install -y /tmp/tableau-bridge.rpm && \
    rm -f /tmp/tableau-bridge.rpm

# 4. Copy ODBC configuration and entrypoint script
COPY odbcinst.ini /etc/odbcinst.ini
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 5. Create directory for Tableau Bridge logs
RUN mkdir -p /root/Documents/My_Tableau_Bridge_Repository/Log

WORKDIR /opt/tableau/tableau_bridge/bin

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
