FROM ruby:2.7-alpine

RUN apk add --no-cache easy-rsa git \
    # Hack until easy-rsa 3.0.7 is released https://github.com/OpenVPN/easy-rsa/issues/261
    && sed -i 's/^RANDFILE\s*=\s\$ENV.*/#&/' /usr/share/easy-rsa/openssl-easyrsa.cnf \
    && ln -s /usr/share/easy-rsa/easyrsa  /usr/bin/

ENV EASYRSA=/usr/share/easy-rsa
ENV EASYRSA_BATCH=yes

ARG CFNVPN_VERSION="0.5.0"

COPY . /src

WORKDIR /src

RUN gem build cfn-vpn.gemspec \
    && gem install cfn-vpn-${CFNVPN_VERSION}.gem \
    && rm -rf /src
    
RUN addgroup -g 1000 cfnvpn && \
    adduser -D -u 1000 -G cfnvpn cfnvpn

USER cfnvpn

RUN cfndsl -u 9.0.0