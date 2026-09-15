# Bakes the mechanism-comparison dashboard into a portable image.
# The page is fully self-contained static HTML (no backend calls, no fetch), so nginx
# serving one file is the entire runtime: nothing to connect to, nothing that can fail
# to start, no dependency on Oracle or Kafka being up.
#
# Build (context = docs/, so COPY below resolves against it):
#   docker build -f docker/dashboard/Dockerfile -t obsv/mechanism-dashboard:local docs
#
# Run standalone, no compose needed:
#   docker run -d --name obsv-dashboard -p 8082:80 obsv/mechanism-dashboard:local
FROM nginx:1.27-alpine
COPY mechanism-comparison.html /usr/share/nginx/html/index.html
EXPOSE 80
