FROM alpine:latest

ENV PROTO=vless
ENV USER_ID=changeme
ENV WS_PATH=/ws

RUN apk add --no-cache curl unzip \
 && curl -L -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip \
 && unzip /tmp/xray.zip -d /usr/local/bin \
 && chmod +x /usr/local/bin/xray

COPY config.json.tpl /config.json.tpl

CMD sh -c "sed \
  -e \"s|__PROTO__|$PROTO|g\" \
  -e \"s|__USER_ID__|$USER_ID|g\" \
  -e \"s|__WS_PATH__|$WS_PATH|g\" \
  /config.json.tpl > /tmp/config.json && \
  /usr/local/bin/xray run -config /tmp/config.json"