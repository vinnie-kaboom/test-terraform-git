FROM alpine:latest

RUN apk add --no-cache python3

WORKDIR /workspace

COPY . /workspace/

CMD ["python3", "--version"]