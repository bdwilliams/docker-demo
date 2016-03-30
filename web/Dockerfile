FROM golang:1.6.0-alpine

RUN apk update && apk add git
RUN mkdir -p /opt
ADD web.go /opt
RUN cd /opt && go get -d . && go build web.go

EXPOSE 8080
ENTRYPOINT ["/opt/web"]