FROM golang:latest AS builder

WORKDIR /app

COPY go.mod go.sum /app/

RUN go mod download

COPY . .

RUN make build-static

FROM gcr.io/distroless/base-debian12:nonroot

COPY --from=builder /app/build/eth-lsd-ejector /app

ENTRYPOINT [ "/app" ] 