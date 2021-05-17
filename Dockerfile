#FROM reesh/elm-platform:0.19.1
#WORKDIR /usr/src/morphir-elm
#COPY . .

FROM node:16.1-alpine3.11
LABEL author="Piyush Gupta"
ENV  NODE_ENV=production
ENV PORT=3000

#Directory of Docker Container
WORKDIR /var/www

COPY . ./

WORKDIR /var/www/tests-integration/reference-model

RUN npm install -g morphir-elm


EXPOSE $PORT
ENTRYPOINT ["morphir-elm","develop"]