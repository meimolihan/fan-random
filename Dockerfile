FROM node:20-alpine

WORKDIR /fan-random

# 复制应用代码和全部壁纸图片
COPY public/ ./public/
COPY api/ ./api/
COPY bin/ ./bin/
COPY docker-server.js ./
COPY package.json ./

RUN chmod +x /fan-random/bin/fan-random.js \
    && ln -sf /fan-random/bin/fan-random.js /usr/local/bin/fan-random

ENV PORT=3000
EXPOSE 3000

CMD ["node", "docker-server.js"]