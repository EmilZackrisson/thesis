FROM golang:1.26-trixie AS build-stage
WORKDIR /app
COPY go.mod ./

COPY *.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -o /tcptrafficgenerator


FROM gcr.io/distroless/base-debian13 AS build-release-stage

WORKDIR /

COPY --from=build-stage /tcptrafficgenerator /tcptrafficgenerator

USER nonroot:nonroot

EXPOSE 9000

CMD ["/tcptrafficgenerator", "-mode=server", "-port=9000"]