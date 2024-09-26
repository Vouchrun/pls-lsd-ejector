FROM golang:latest AS builder

WORKDIR /app

COPY go.mod go.sum /app/

RUN go mod download

COPY . .

RUN make build

FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app

COPY --from=builder /app/build/eth-lsd-ejector ./eth-lsd-ejector

ENTRYPOINT [ "/app/eth-lsd-ejector", "start" ]
# CMD [ "start" ]