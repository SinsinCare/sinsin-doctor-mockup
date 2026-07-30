FROM nginx:1.27.5-alpine

COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html demo.html HANDOFF.md API.md README.md /usr/share/nginx/html/

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --spider http://127.0.0.1:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
