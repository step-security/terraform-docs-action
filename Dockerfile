# Copyright 2021 The terraform-docs Authors.
# Copyright 2025 Step Security.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM golang:1.26-alpine3.23@sha256:f85330846cde1e57ca9ec309382da3b8e6ae3ab943d2739500e08c86393a21b1
ARG TERRAFORM_DOCS_VERSION=v0.21.0

# Install dependencies
RUN set -eux; \
    apk update; \
    apk add --no-cache \
      bash \
      git \
      git-lfs \
      jq \
      openssh \
      sed \
      yq \
      curl \
      build-base \
      ca-certificates; \
    update-ca-certificates

# Clone terraform-docs source
WORKDIR /app
RUN git clone --depth 1 --branch "${TERRAFORM_DOCS_VERSION}" https://github.com/terraform-docs/terraform-docs.git .

# Build terraform-docs binary (for v0.20.x main.go is at repo root)
ENV CGO_ENABLED=0
RUN go get google.golang.org/grpc@v1.79.3 && go mod tidy
RUN go build -trimpath -ldflags="-s -w" -o /usr/local/bin/terraform-docs .

# Verify install
RUN terraform-docs --version

# Copy entrypoint
COPY ./src/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

