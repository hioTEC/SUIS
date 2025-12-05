# Minimal Docker Command Proxy
# This sidecar has docker.sock access but only executes whitelisted commands
FROM alpine:3.19

RUN apk add --no-cache docker-cli socat

COPY proxy.sh /proxy.sh
RUN chmod +x /proxy.sh

# Run as non-root where possible
USER root

CMD ["/proxy.sh"]
