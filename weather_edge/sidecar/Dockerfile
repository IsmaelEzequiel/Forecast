FROM node:20-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --production

COPY index.js ./

USER node

CMD ["node", "index.js"]
