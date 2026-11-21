# ResQ-CD Phase 2: Blue-Green Deploy

Files to create:
deploy/docker-compose.yml   services: nginx only (port 8080), network resqcd-net (external)
deploy/nginx/default.conf   server { listen 80; location / { proxy_pass http://app; } } and include /etc/nginx/active/upstream.conf
deploy/nginx/active/upstream.conf   upstream app { server blue:8080; }
deploy/deploy.sh            blue-green deploy script
deploy/state/               active_color (default blue), history.json

deploy.sh (arg: IMAGE_TAG), run with Git Bash:
1. Read deploy/state/active_color (default blue). NEW = the other color.
2. Start container NEW (name = NEW) from image resqcd:IMAGE_TAG on network resqcd-net. Pass env BREAK_HEALTH if set.
3. Health check NEW at http://NEW:8080/actuator/health from a curl container on resqcd-net. Retry 10x, 3s gap.
4. If fail: remove NEW, log FAILED_HEALTHCHECK, exit 1. Active untouched.
5. If pass: write upstream.conf pointing to NEW, run `docker exec nginx nginx -s reload`, update active_color.
6. Post-switch verify: curl http://localhost:8080/actuator/health 5 times over 15s.
7. If fail: switch upstream back to OLD, reload, log ROLLED_BACK, exit 1.
8. If pass: log SUCCESS, remove OLD container.
history.json is an array of {timestamp, version, color, status, reason, duration_sec}.