# Debezium Connect plus a JMX→Prometheus agent, so the thesis can measure connector-side
# metrics (MilliSecondsBehindSource, CurrentScn, NumberOfLargeTransactions, ...) rather
# than inferring pipeline lag from the sink alone.
FROM quay.io/debezium/connect:3.5

USER root
ARG JMX_AGENT_VERSION=1.0.1
RUN mkdir -p /kafka/jmx && \
    curl -fsSL -o /kafka/jmx/jmx_prometheus_javaagent.jar \
      "https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_AGENT_VERSION}/jmx_prometheus_javaagent-${JMX_AGENT_VERSION}.jar"
COPY connect-jmx.yml /kafka/jmx/connect.yml
RUN chown -R kafka:kafka /kafka/jmx
USER kafka
