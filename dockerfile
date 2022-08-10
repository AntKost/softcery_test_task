FROM golang:alpine3.16

WORKDIR /usr/src/app
COPY . .

RUN go get -u github.com/gin-gonic/gin
RUN go build server.go
EXPOSE 8080

CMD ["./server"]